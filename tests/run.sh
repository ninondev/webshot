#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Ninon

set -u

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
cd "$root" || exit 1
webshot=${WEBSHOT_BIN:-./build/webshot}
pixelcheck=${PIXELCHECK_BIN:-./build/pixelcheck}
temp_base=${WEBSHOT_TEST_TMP:-${TMPDIR:-/tmp}}

if [ ! -x "$webshot" ] || [ ! -x "$pixelcheck" ]; then
    printf 'FAIL: build webshot and pixelcheck first with make\n' >&2
    printf 'Tests: 0 passed, 1 failed, 0 skipped\n'
    exit 1
fi
mkdir -p "$temp_base" || exit 1
work=$(mktemp -d "$temp_base/webshot-tests.XXXXXX") || exit 1
passed=0
failed=0
fixture="$root/tests/fixtures"

run_case() {
    name=$1
    shift
    if "$@" >"$work/$name.log" 2>&1; then
        passed=$((passed + 1))
        printf 'PASS: %s\n' "$name"
    else
        failed=$((failed + 1))
        printf 'FAIL: %s\n' "$name"
        cat "$work/$name.log"
    fi
}

dimensions() {
    details=$(sips -g pixelWidth -g pixelHeight "$1") || return 1
    actual_width=$(printf '%s\n' "$details" | awk '/pixelWidth:/ {print $2}')
    actual_height=$(printf '%s\n' "$details" | awk '/pixelHeight:/ {print $2}')
    if [ "$actual_width" != "$2" ] || [ "$actual_height" != "$3" ]; then
        printf 'Expected %sx%s, got %sx%s\n' "$2" "$3" "$actual_width" "$actual_height" >&2
        return 1
    fi
}

pixel() {
    input=$1
    x=$2
    y=$3
    crop="$work/pixel-$x-$y.png"
    sips --cropToHeightWidth 1 1 --cropOffset "$y" "$x" "$input" --out "$crop" >/dev/null || return 1
    "$pixelcheck" "$crop" "$4" "$5" "$6" 3
}

render() {
    "$webshot" "$@" --timeout 4000
}

plain() {
    render "$fixture/plain.html" "$work/plain.png" --width 160 --scale 2 || return 1
    dimensions "$work/plain.png" 320 2400 || return 1
    pixel "$work/plain.png" 20 100 200 50 50 || return 1
    pixel "$work/plain.png" 20 1000 50 150 90 || return 1
    pixel "$work/plain.png" 20 2200 50 80 200
}

light() {
    render "$fixture/theme.html" "$work/light.png" --width 160 --scale 1 --theme light || return 1
    dimensions "$work/light.png" 160 240 || return 1
    pixel "$work/light.png" 20 20 250 240 220
}

dark() {
    render "$fixture/theme.html" "$work/dark.png" --width 160 --scale 1 --theme dark || return 1
    dimensions "$work/dark.png" 160 240 || return 1
    pixel "$work/dark.png" 20 20 24 36 50
}

javascript() {
    render "$fixture/javascript.html" "$work/javascript.png" --width 160 --scale 1 --wait 200 \
        --js 'document.body.dataset.state' >"$work/javascript.stdout" || return 1
    [ "$(cat "$work/javascript.stdout")" = ready ] || {
        printf 'Expected --js to print ready\n' >&2
        cat "$work/javascript.stdout"
        return 1
    }
    dimensions "$work/javascript.png" 160 280 || return 1
    pixel "$work/javascript.png" 20 260 50 150 90
}

maximum_height() {
    render "$fixture/plain.html" "$work/maximum.png" --width 160 --scale 2 --max-height 450 || return 1
    dimensions "$work/maximum.png" 320 900 || return 1
    pixel "$work/maximum.png" 20 850 50 150 90
}

clip() {
    render "$fixture/plain.html" "$work/clip.png" --width 160 --scale 2 --clip 20,450,40,80 || return 1
    dimensions "$work/clip.png" 80 160 || return 1
    pixel "$work/clip.png" 10 10 50 150 90
}

fractional_scale() {
    render "$fixture/plain.html" "$work/fractional.png" --width 160 --scale 1.25 || return 1
    dimensions "$work/fractional.png" 200 1500 || return 1
    pixel "$work/fractional.png" 20 1300 50 80 200
}

expect_failure() {
    label=$1
    pattern=$2
    shift 2
    if "$webshot" "$@" >"$work/$label.stdout" 2>"$work/$label.stderr"; then
        printf 'Expected a non-zero exit\n' >&2
        return 1
    fi
    if ! grep -Eiq "$pattern" "$work/$label.stderr"; then
        printf 'Expected error matching: %s\n' "$pattern" >&2
        cat "$work/$label.stderr"
        return 1
    fi
    if [ -s "$work/$label.stdout" ]; then
        printf 'Error diagnostics unexpectedly written to stdout\n' >&2
        cat "$work/$label.stdout"
        return 1
    fi
}

timeout() {
    expect_failure timeout 'tim(e|ed)[ -]?out|timeout' "$fixture/plain.html" "$work/timeout.png" \
        --width 160 --wait 2000 --timeout 500 || return 1
    [ ! -e "$work/timeout.png" ]
}

run_case plain plain
run_case light light
run_case dark dark
run_case javascript javascript
run_case maximum-height maximum_height
run_case clip clip
run_case fractional-scale fractional_scale
run_case missing-input expect_failure missing-input 'not found|does not exist|cannot (read|open)|no such file|missing' \
    "$work/missing.html" "$work/missing.png"
run_case invalid-width expect_failure invalid-width 'width' \
    "$fixture/plain.html" "$work/invalid-width.png" --width 0
run_case invalid-theme expect_failure invalid-theme 'theme' \
    "$fixture/plain.html" "$work/invalid-theme.png" --theme blue
run_case unknown-option expect_failure unknown-option 'unknown|unrecognized|unexpected' \
    "$fixture/plain.html" "$work/unknown.png" --wat
run_case invalid-clip expect_failure invalid-clip 'clip' \
    "$fixture/plain.html" "$work/invalid-clip.png" --clip 0,0,-1,50
run_case timeout timeout

printf 'Tests: %s passed, %s failed, 0 skipped\n' "$passed" "$failed"
printf 'Test files and logs: %s\n' "$work"
[ "$failed" -eq 0 ]
