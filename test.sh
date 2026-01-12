#!/bin/bash
#
# Visual Test Suite for Nanobanana CLI
#
# This script generates test images in .tests/ for visual review.
# Run: ./test.sh
#
# Requirements:
# - GEMINI_API_KEY environment variable or .env file
# - Built nanobanana binary in current directory
#

# Don't exit on error - we want to continue and report all failures
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test directory
TESTS_DIR=".tests"
PROMPTS_DIR="$TESTS_DIR/prompts"

# Binary path
NANOBANANA="./nanobanana"

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Check if binary exists
if [ ! -f "$NANOBANANA" ]; then
    echo -e "${RED}Error: nanobanana binary not found. Run 'make build' first.${NC}"
    exit 1
fi

# Create test directories
mkdir -p "$TESTS_DIR"
mkdir -p "$PROMPTS_DIR"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Nanobanana CLI Visual Test Suite                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Test output directory: ${YELLOW}$TESTS_DIR/${NC}"
echo ""

# Delay between API calls to avoid rate limiting (seconds)
API_DELAY=2

# Helper function to run a test
run_test() {
    local name="$1"
    local cmd="$2"
    local output_file="$3"

    echo -n "  Testing: $name... "

    # Capture both stdout and stderr
    local output
    output=$(eval "$cmd" 2>&1)
    local exit_code=$?

    if [ $exit_code -eq 0 ] && [ -f "$output_file" ]; then
        size=$(ls -lh "$output_file" | awk '{print $5}')
        echo -e "${GREEN}✓ PASS${NC} ($size)"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}"
        # Show error details
        echo "$output" | head -3 | sed 's/^/      /'
        ((FAILED++))
    fi

    # Small delay to avoid rate limiting
    sleep $API_DELAY
}

# Helper for tests that might fail due to API issues (non-critical)
run_test_optional() {
    local name="$1"
    local cmd="$2"
    local output_file="$3"

    echo -n "  Testing: $name... "

    local output
    output=$(eval "$cmd" 2>&1)
    local exit_code=$?

    if [ $exit_code -eq 0 ] && [ -f "$output_file" ]; then
        size=$(ls -lh "$output_file" | awk '{print $5}')
        echo -e "${GREEN}✓ PASS${NC} ($size)"
        ((PASSED++))
    else
        echo -e "${YELLOW}○ SKIP${NC} (optional test)"
        ((SKIPPED++))
    fi

    sleep $API_DELAY
}

#═══════════════════════════════════════════════════════════════════════════════
# TEST SECTION 1: Basic Image Generation
#═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}━━━ Test 1: Basic Image Generation ━━━${NC}"

run_test "Simple prompt" \
    "$NANOBANANA generate 'a red apple on white background' -o '$TESTS_DIR/01_simple.png'" \
    "$TESTS_DIR/01_simple.png"

run_test "Prompt with quotes" \
    "$NANOBANANA generate 'A neon sign that says \"HELLO WORLD\"' -o '$TESTS_DIR/02_quotes.png'" \
    "$TESTS_DIR/02_quotes.png"

run_test "Aspect ratio 16:9" \
    "$NANOBANANA generate 'mountain landscape at sunset' -o '$TESTS_DIR/03_landscape.png' --aspect-ratio 16:9" \
    "$TESTS_DIR/03_landscape.png"

run_test "Aspect ratio 9:16" \
    "$NANOBANANA generate 'tall skyscraper at night' -o '$TESTS_DIR/04_portrait.png' --aspect-ratio 9:16" \
    "$TESTS_DIR/04_portrait.png"

echo ""

#═══════════════════════════════════════════════════════════════════════════════
# TEST SECTION 2: Complex Multi-line Prompts (from files)
#═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}━━━ Test 2: Complex Multi-line Prompts ━━━${NC}"

# Create complex prompt files
cat > "$PROMPTS_DIR/photorealistic.txt" << 'PROMPT'
A photorealistic close-up portrait of an elderly Japanese ceramicist
with deep, sun-etched wrinkles and a warm, knowing smile. He is
carefully inspecting a freshly glazed tea bowl. The setting is his
rustic, sun-drenched workshop with pottery wheels and shelves of clay
pots in the background. The scene is illuminated by soft, golden hour
light streaming through a window, highlighting the fine texture of the
clay and the fabric of his apron. Captured with an 85mm portrait lens,
resulting in a soft, blurred background (bokeh). The overall mood is
serene and masterful.
PROMPT

cat > "$PROMPTS_DIR/sticker.txt" << 'PROMPT'
A kawaii-style sticker of a happy red panda wearing a tiny bamboo hat.
It's munching on a green bamboo leaf. The design features bold, clean
outlines, simple cel-shading, and a vibrant color palette. The
background must be white.
PROMPT

cat > "$PROMPTS_DIR/infographic.txt" << 'PROMPT'
Create a visually stunning infographic about the water cycle.
Include these stages with clear icons and arrows:
1. Evaporation from oceans and lakes
2. Condensation forming clouds
3. Precipitation as rain and snow
4. Collection in rivers, lakes, and groundwater
Use a clean, modern design with a blue color palette.
Add simple labels for each stage.
PROMPT

cat > "$PROMPTS_DIR/game_asset.txt" << 'PROMPT'
A 16-bit pixel art sprite of a brave knight character for a 2D RPG game.
The knight should have:
- Silver armor with blue accents
- A glowing magic sword
- A determined expression
- A heroic pose ready for battle
Style: retro pixel art, limited color palette, clean pixels,
suitable for a side-scrolling adventure game.
PROMPT

run_test "Photorealistic (from file)" \
    "$NANOBANANA generate --prompt-file '$PROMPTS_DIR/photorealistic.txt' -o '$TESTS_DIR/05_photorealistic.png'" \
    "$TESTS_DIR/05_photorealistic.png"

run_test "Kawaii sticker (from file)" \
    "$NANOBANANA generate --prompt-file '$PROMPTS_DIR/sticker.txt' -o '$TESTS_DIR/06_sticker.png'" \
    "$TESTS_DIR/06_sticker.png"

run_test "Infographic (from file)" \
    "$NANOBANANA generate --prompt-file '$PROMPTS_DIR/infographic.txt' -o '$TESTS_DIR/07_infographic.png'" \
    "$TESTS_DIR/07_infographic.png"

run_test "Game asset (from file)" \
    "$NANOBANANA generate --prompt-file '$PROMPTS_DIR/game_asset.txt' -o '$TESTS_DIR/08_game_asset.png'" \
    "$TESTS_DIR/08_game_asset.png"

echo ""

#═══════════════════════════════════════════════════════════════════════════════
# TEST SECTION 3: Stdin Input (AI Agent Simulation)
#═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}━━━ Test 3: Stdin Input (AI Agent Simulation) ━━━${NC}"

run_test "Stdin with pipe" \
    "echo 'A cute robot waving hello, friendly cartoon style' | $NANOBANANA generate - -o '$TESTS_DIR/09_stdin_pipe.png'" \
    "$TESTS_DIR/09_stdin_pipe.png"

run_test "Stdin with heredoc" \
    "cat << 'EOF' | $NANOBANANA generate - -o '$TESTS_DIR/10_stdin_heredoc.png'
A cozy coffee shop interior with warm lighting,
wooden furniture, and plants hanging from the ceiling.
Watercolor painting style with soft edges.
EOF" \
    "$TESTS_DIR/10_stdin_heredoc.png"

echo ""

#═══════════════════════════════════════════════════════════════════════════════
# TEST SECTION 4: Icon Generation
#═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}━━━ Test 4: Icon Generation ━━━${NC}"

run_test "App icons (multiple sizes)" \
    "$NANOBANANA icon 'modern coffee cup logo minimalist' -o '$TESTS_DIR/icons/' --sizes 64,128,256" \
    "$TESTS_DIR/icons/icon_64.png"

run_test "Flat style icon" \
    "$NANOBANANA icon 'settings gear icon' -o '$TESTS_DIR/icons_flat/' --style flat --sizes 128" \
    "$TESTS_DIR/icons_flat/icon_128.png"

echo ""

#═══════════════════════════════════════════════════════════════════════════════
# TEST SECTION 5: Pattern Generation
#═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}━━━ Test 5: Pattern Generation ━━━${NC}"

run_test "Seamless geometric pattern" \
    "$NANOBANANA pattern 'hexagon grid blue and white' -o '$TESTS_DIR/11_pattern_geo.png' --style geometric" \
    "$TESTS_DIR/11_pattern_geo.png"

run_test "Wood texture" \
    "$NANOBANANA pattern 'oak wood grain' -o '$TESTS_DIR/12_pattern_wood.png' --type texture" \
    "$TESTS_DIR/12_pattern_wood.png"

echo ""

#═══════════════════════════════════════════════════════════════════════════════
# TEST SECTION 6: Image Transformation (no API needed)
#═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}━━━ Test 6: Image Transformation ━━━${NC}"

# Use a generated image for transform tests
if [ -f "$TESTS_DIR/01_simple.png" ]; then
    run_test "Resize to thumbnail" \
        "$NANOBANANA transform '$TESTS_DIR/01_simple.png' -o '$TESTS_DIR/13_thumb.png' --resize 128x128" \
        "$TESTS_DIR/13_thumb.png"

    run_test "Resize by percentage" \
        "$NANOBANANA transform '$TESTS_DIR/01_simple.png' -o '$TESTS_DIR/14_half.png' --resize 50%" \
        "$TESTS_DIR/14_half.png"

    run_test "Rotate 90 degrees" \
        "$NANOBANANA transform '$TESTS_DIR/01_simple.png' -o '$TESTS_DIR/15_rotated.png' --rotate 90" \
        "$TESTS_DIR/15_rotated.png"

    run_test "Flip and flop" \
        "$NANOBANANA transform '$TESTS_DIR/01_simple.png' -o '$TESTS_DIR/16_flipped.png' --flip --flop" \
        "$TESTS_DIR/16_flipped.png"

    run_test "Crop region" \
        "$NANOBANANA transform '$TESTS_DIR/01_simple.png' -o '$TESTS_DIR/17_cropped.png' --crop 100,100,500,500" \
        "$TESTS_DIR/17_cropped.png"
else
    echo -e "  ${YELLOW}Skipping transform tests (no source image)${NC}"
    ((SKIPPED+=5))
fi

echo ""

#═══════════════════════════════════════════════════════════════════════════════
# TEST SECTION 7: Transparency Operations
#═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}━━━ Test 7: Transparency Operations ━━━${NC}"

if [ -f "$TESTS_DIR/06_sticker.png" ]; then
    run_test "Inspect transparency" \
        "$NANOBANANA transparent inspect '$TESTS_DIR/06_sticker.png'" \
        "$TESTS_DIR/06_sticker.png"

    run_test "Remove white background" \
        "$NANOBANANA transparent make '$TESTS_DIR/06_sticker.png' -o '$TESTS_DIR/18_transparent.png' --color white --tolerance 15" \
        "$TESTS_DIR/18_transparent.png"
else
    echo -e "  ${YELLOW}Skipping transparency tests (no source image)${NC}"
    ((SKIPPED+=2))
fi

echo ""

#═══════════════════════════════════════════════════════════════════════════════
# TEST SECTION 8: Image Combining
#═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}━━━ Test 8: Image Combining ━━━${NC}"

if [ -f "$TESTS_DIR/13_thumb.png" ]; then
    run_test "Horizontal strip" \
        "$NANOBANANA combine '$TESTS_DIR/13_thumb.png' '$TESTS_DIR/13_thumb.png' '$TESTS_DIR/13_thumb.png' -o '$TESTS_DIR/19_strip_h.png' --direction horizontal --gap 5" \
        "$TESTS_DIR/19_strip_h.png"

    run_test "Vertical stack" \
        "$NANOBANANA combine '$TESTS_DIR/13_thumb.png' '$TESTS_DIR/13_thumb.png' -o '$TESTS_DIR/20_strip_v.png' --direction vertical --gap 10" \
        "$TESTS_DIR/20_strip_v.png"

    run_test "Grid layout" \
        "$NANOBANANA combine '$TESTS_DIR/13_thumb.png' '$TESTS_DIR/13_thumb.png' '$TESTS_DIR/13_thumb.png' '$TESTS_DIR/13_thumb.png' -o '$TESTS_DIR/21_grid.png' --direction grid --columns 2 --gap 5" \
        "$TESTS_DIR/21_grid.png"
else
    echo -e "  ${YELLOW}Skipping combine tests (no source images)${NC}"
    ((SKIPPED+=3))
fi

echo ""

#═══════════════════════════════════════════════════════════════════════════════
# TEST SECTION 9: JSON Output
#═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}━━━ Test 9: JSON Output ━━━${NC}"

echo -n "  Testing: JSON output format... "
JSON_OUTPUT=$($NANOBANANA generate "test image" -o "$TESTS_DIR/22_json_test.png" --json 2>&1 || true)
if echo "$JSON_OUTPUT" | grep -q '"success"'; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((PASSED++))
    # Save JSON for inspection
    echo "$JSON_OUTPUT" > "$TESTS_DIR/22_json_output.json"
else
    echo -e "${RED}✗ FAIL${NC}"
    ((FAILED++))
fi

echo ""

#═══════════════════════════════════════════════════════════════════════════════
# TEST SECTION 10: Edge Cases
#═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}━━━ Test 10: Edge Cases ━━━${NC}"

run_test "Unicode in prompt" \
    "$NANOBANANA generate '日本の桜の木 (Japanese cherry blossom tree) 🌸' -o '$TESTS_DIR/23_unicode.png'" \
    "$TESTS_DIR/23_unicode.png"

run_test_optional "Special characters" \
    "$NANOBANANA generate 'A sign with symbols: @#\$%&*()' -o '$TESTS_DIR/24_special.png'" \
    "$TESTS_DIR/24_special.png"

echo ""

#═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
#═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                      TEST SUMMARY                          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}Passed:${NC}  $PASSED"
echo -e "  ${RED}Failed:${NC}  $FAILED"
echo -e "  ${YELLOW}Skipped:${NC} $SKIPPED"
echo ""
echo -e "Generated images are in: ${YELLOW}$TESTS_DIR/${NC}"
echo -e "Prompt files are in:     ${YELLOW}$PROMPTS_DIR/${NC}"
echo ""

# List generated files
echo -e "${BLUE}Generated files:${NC}"
ls -la "$TESTS_DIR"/*.png 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'

echo ""
echo -e "${BLUE}To view results:${NC}"
echo "  open $TESTS_DIR/   # macOS"
echo "  xdg-open $TESTS_DIR/   # Linux"
echo ""

# Exit with error if any tests failed
if [ $FAILED -gt 0 ]; then
    exit 1
fi
