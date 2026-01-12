package cli

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/lyalindotcom/nano-banana-cli/internal/gemini"
	"github.com/lyalindotcom/nano-banana-cli/internal/output"
	"github.com/spf13/cobra"
)

var (
	// Generate command flags
	outputPath  string
	inputPath   string
	promptFile  string
	count       int
	aspectRatio string
	resolution  string
	noOverwrite bool
)

var generateCmd = &cobra.Command{
	Use:   "generate [prompt]",
	Short: "Generate images from text prompts",
	Long: `Generate images from text prompts using Gemini's native image generation.

This command supports:
  - Text-to-image: Generate new images from text descriptions
  - Image editing: Modify existing images with text instructions (use -i flag)

PROMPT INPUT:
  - As arguments: nanobanana generate "your prompt here"
  - From file: nanobanana generate --prompt-file prompt.txt -o out.png
  - From stdin: echo "prompt" | nanobanana generate - -o out.png
  - From stdin: nanobanana generate -o out.png < prompt.txt

MODELS:
  - flash (default): Gemini 2.5 Flash - Fast generation
  - pro: Gemini 3 Pro - Higher quality, supports 4K resolution

ASPECT RATIOS:
  1:1 (default), 3:2, 2:3, 3:4, 4:3, 4:5, 5:4, 9:16, 16:9, 21:9

RESOLUTIONS (pro model only):
  1K (default), 2K, 4K

EXAMPLES:
  # Generate a simple image
  nanobanana generate "a sunset over mountains" -o sunset.png

  # Generate with specific aspect ratio
  nanobanana generate "landscape photo" -o landscape.png --aspect-ratio 16:9

  # Generate with pro model for higher quality
  nanobanana generate "detailed portrait" -o portrait.png -m pro --resolution 4K

  # Edit an existing image
  nanobanana generate "add sunglasses" -i face.png -o face-sunglasses.png

  # Generate multiple variations
  nanobanana generate "abstract art" -o art.png --count 4

  # Complex multi-line prompt from file
  nanobanana generate --prompt-file detailed-scene.txt -o scene.png

  # Prompt from stdin (useful for AI agents)
  cat << 'EOF' | nanobanana generate - -o portrait.png
  A photorealistic close-up portrait of an elderly Japanese ceramicist
  with deep, sun-etched wrinkles and a warm, knowing smile.
  EOF`,
	Args: cobra.MinimumNArgs(0),
	RunE: runGenerate,
}

func init() {
	generateCmd.Flags().StringVarP(&outputPath, "output", "o", "", "Output file path (required)")
	generateCmd.Flags().StringVarP(&inputPath, "input", "i", "", "Input image for editing")
	generateCmd.Flags().StringVarP(&promptFile, "prompt-file", "p", "", "Read prompt from file (supports multi-line)")
	generateCmd.Flags().IntVarP(&count, "count", "c", 1, "Number of images to generate (1-10)")
	generateCmd.Flags().StringVar(&aspectRatio, "aspect-ratio", "1:1", "Aspect ratio: 1:1, 16:9, 9:16, 4:3, 3:4, etc.")
	generateCmd.Flags().StringVar(&resolution, "resolution", "", "Resolution: 1K, 2K, 4K (4K only with pro model)")
	generateCmd.Flags().BoolVar(&noOverwrite, "no-overwrite", false, "Fail if output file exists")

	generateCmd.MarkFlagRequired("output")
}

func runGenerate(cmd *cobra.Command, args []string) error {
	f := GetFormatter()
	startTime := time.Now()

	// Get prompt from various sources
	prompt, err := getPrompt(args)
	if err != nil {
		f.Error("generate", "PROMPT_ERROR", err.Error(), "Provide prompt as argument, --prompt-file, or stdin")
		return err
	}

	if strings.TrimSpace(prompt) == "" {
		f.Error("generate", "EMPTY_PROMPT", "Prompt cannot be empty",
			"Provide prompt as argument, --prompt-file, or stdin")
		return fmt.Errorf("empty prompt")
	}

	// Validate API key
	apiKey := GetAPIKey()
	if apiKey == "" {
		f.Error("generate", "MISSING_API_KEY", "No API key provided",
			"Set GEMINI_API_KEY environment variable or use --api-key flag")
		return fmt.Errorf("missing API key")
	}

	// Validate flags
	if count < 1 || count > 10 {
		f.Error("generate", "INVALID_COUNT", "Count must be between 1 and 10", "")
		return fmt.Errorf("invalid count")
	}

	if aspectRatio != "" && !gemini.IsValidAspectRatio(aspectRatio) {
		f.Error("generate", "INVALID_ASPECT_RATIO",
			fmt.Sprintf("Invalid aspect ratio: %s", aspectRatio),
			fmt.Sprintf("Valid ratios: %s", strings.Join(gemini.AspectRatios, ", ")))
		return fmt.Errorf("invalid aspect ratio")
	}

	// Check for existing file
	if noOverwrite {
		if _, err := os.Stat(outputPath); err == nil {
			f.Error("generate", "FILE_EXISTS",
				fmt.Sprintf("Output file already exists: %s", outputPath),
				"Use a different output path or remove --no-overwrite flag")
			return fmt.Errorf("file exists")
		}
	}

	// Create client
	modelName := gemini.ResolveModelName(GetModel())
	client, err := gemini.NewClient(apiKey, modelName, 2*time.Minute)
	if err != nil {
		f.Error("generate", "CLIENT_ERROR", err.Error(), "Check your API key")
		return err
	}

	// Build config
	config := &gemini.ImageConfig{
		AspectRatio: aspectRatio,
		Resolution:  resolution,
		Count:       count,
	}

	f.Progress("Generating image with %s...", modelName)

	// Generate or edit
	ctx := context.Background()
	var images []*gemini.GeneratedImage

	if inputPath != "" {
		// Edit mode
		if _, err := os.Stat(inputPath); os.IsNotExist(err) {
			f.Error("generate", "FILE_NOT_FOUND",
				fmt.Sprintf("Input file not found: %s", inputPath), "")
			return err
		}
		f.Progress("Editing image: %s", inputPath)
		images, err = client.EditImage(ctx, inputPath, prompt, config)
	} else {
		// Generate mode
		images, err = client.GenerateImage(ctx, prompt, config)
	}

	if err != nil {
		if geminiErr, ok := err.(*gemini.GeminiError); ok {
			hint := ""
			switch geminiErr.Code {
			case gemini.ErrInvalidAPIKey:
				hint = "Check your API key at https://aistudio.google.com/apikey"
			case gemini.ErrQuotaExceeded:
				hint = "Wait before retrying or check your quota"
			case gemini.ErrSafetyBlocked:
				hint = "Try rephrasing your prompt"
			}
			f.Error("generate", geminiErr.Code, geminiErr.Message, hint)
		} else {
			f.Error("generate", "GENERATION_FAILED", err.Error(), "")
		}
		return err
	}

	// Save images
	var results []output.ImageResult
	for i, img := range images {
		savePath := outputPath
		if len(images) > 1 {
			ext := filepath.Ext(outputPath)
			base := strings.TrimSuffix(outputPath, ext)
			savePath = fmt.Sprintf("%s_%d%s", base, i+1, ext)
		}

		if err := client.SaveImage(img, savePath); err != nil {
			f.Error("generate", "SAVE_FAILED", err.Error(), "")
			return err
		}

		// Get dimensions (approximate based on mime type)
		width, height := estimateDimensions(aspectRatio)
		f.ImageSaved(savePath, width, height)

		results = append(results, output.ImageResult{
			Path:   savePath,
			Format: strings.TrimPrefix(img.MimeType, "image/"),
			Size:   &output.ImageSize{Width: width, Height: height},
		})
	}

	// Output success
	elapsed := time.Since(startTime)
	timing := &output.Timing{
		TotalMs: elapsed.Milliseconds(),
	}

	data := map[string]interface{}{
		"prompt": prompt,
		"model":  modelName,
		"images": results,
	}

	f.Success("generate", data, timing)
	return nil
}

// getPrompt retrieves the prompt from arguments, file, or stdin
func getPrompt(args []string) (string, error) {
	// Priority 1: --prompt-file flag
	if promptFile != "" {
		data, err := os.ReadFile(promptFile)
		if err != nil {
			return "", fmt.Errorf("failed to read prompt file: %w", err)
		}
		return string(data), nil
	}

	// Priority 2: stdin (when "-" is passed or when piped)
	if len(args) == 1 && args[0] == "-" {
		return readStdin()
	}

	// Check if stdin has data (piped input)
	if len(args) == 0 {
		stat, _ := os.Stdin.Stat()
		if (stat.Mode() & os.ModeCharDevice) == 0 {
			// Data is being piped
			return readStdin()
		}
		return "", fmt.Errorf("no prompt provided")
	}

	// Priority 3: arguments
	return strings.Join(args, " "), nil
}

// readStdin reads all input from stdin
func readStdin() (string, error) {
	reader := bufio.NewReader(os.Stdin)
	var builder strings.Builder

	for {
		line, err := reader.ReadString('\n')
		builder.WriteString(line)
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", fmt.Errorf("failed to read stdin: %w", err)
		}
	}

	return strings.TrimSpace(builder.String()), nil
}

// estimateDimensions estimates image dimensions based on aspect ratio
func estimateDimensions(ratio string) (int, int) {
	// Default to 1024x1024 for 1:1
	switch ratio {
	case "1:1", "":
		return 1024, 1024
	case "16:9":
		return 1024, 576
	case "9:16":
		return 576, 1024
	case "4:3":
		return 1024, 768
	case "3:4":
		return 768, 1024
	case "3:2":
		return 1024, 683
	case "2:3":
		return 683, 1024
	case "21:9":
		return 1024, 439
	default:
		return 1024, 1024
	}
}
