package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

var (
	activeColor   = lipgloss.Color("10") // bright green
	inactiveColor = lipgloss.Color("8")  // gray
	accentColor   = lipgloss.Color("12") // bright blue
	warningColor  = lipgloss.Color("11") // bright yellow

	activeSessionStyle = lipgloss.NewStyle().
				Foreground(activeColor).
				Bold(true)

	inactiveSessionStyle = lipgloss.NewStyle().
				Foreground(inactiveColor)

	sessionNameStyle = lipgloss.NewStyle().
				Bold(true).
				Foreground(lipgloss.Color("15"))

	windowCountStyle = lipgloss.NewStyle().
				Foreground(warningColor).
				Bold(true)

	headerStyle = lipgloss.NewStyle().
			Foreground(accentColor).
			Bold(true).
			Underline(true).
			MarginBottom(1)
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: tmux-styler <command> [args...]")
		os.Exit(1)
	}

	command := os.Args[1]

	switch command {
	case "sessions":
		styleSessions()
	case "session-info":
		if len(os.Args) < 3 {
			fmt.Println("Usage: tmux-styler session-info <session-name>")
			os.Exit(1)
		}
		styleSessionInfo(os.Args[2])
	default:
		fmt.Printf("Unknown command: %s\n", command)
		os.Exit(1)
	}
}

func styleSessions() {
	// Get tmux sessions
	cmd := exec.Command("tmux", "list-sessions", "-F", "#{session_name}:#{session_attached}:#{session_windows}")
	output, err := cmd.Output()
	if err != nil {
		fmt.Println("No tmux sessions found")
		return
	}

	sessions := strings.Split(strings.TrimSpace(string(output)), "\n")

	header := headerStyle.Render("TMUX SESSIONS")
	fmt.Println(header)

	for _, session := range sessions {
		if session == "" {
			continue
		}

		parts := strings.Split(session, ":")
		if len(parts) < 3 {
			continue
		}

		name := parts[0]
		attached := parts[1] == "1"
		windows := parts[2]

		var indicator string
		var style lipgloss.Style

		if attached {
			indicator = "●"
			style = activeSessionStyle
		} else {
			indicator = "○"
			style = inactiveSessionStyle
		}

		sessionDisplay := fmt.Sprintf("%s %s",
			indicator,
			sessionNameStyle.Render(name))

		windowInfo := windowCountStyle.Render(fmt.Sprintf("(%s windows)", windows))

		fullDisplay := lipgloss.JoinHorizontal(lipgloss.Left,
			style.Render(sessionDisplay),
			" ",
			windowInfo)

		fmt.Println(fullDisplay)
	}

	fmt.Println()
	footer := inactiveSessionStyle.Render("Enter: switch • Ctrl+d: kill • Ctrl+r: rename • Ctrl+n: new")
	fmt.Println(footer)
}

func styleSessionInfo(sessionName string) {
	cmd := exec.Command("tmux", "list-windows", "-t", sessionName, "-F", "#{window_index}:#{window_name}:#{?window_active,1,0}:#{window_panes}")
	output, err := cmd.Output()
	if err != nil {
		fmt.Printf("Session '%s' not found\n", sessionName)
		return
	}

	header := headerStyle.Render(fmt.Sprintf("SESSION: %s", strings.ToUpper(sessionName)))
	fmt.Println(header)

	windows := strings.Split(strings.TrimSpace(string(output)), "\n")
	for _, window := range windows {
		if window == "" {
			continue
		}

		parts := strings.Split(window, ":")
		if len(parts) < 4 {
			continue
		}

		index := parts[0]
		windowName := parts[1]
		isActive := parts[2] == "1"
		panes := parts[3]

		var indicator string
		var style lipgloss.Style

		if isActive {
			indicator = "▶"
			style = activeSessionStyle
		} else {
			indicator = "•"
			style = inactiveSessionStyle
		}

		windowDisplay := fmt.Sprintf("%s %s: %s (%s panes)",
			indicator, index, windowName, panes)

		fmt.Println(style.Render(windowDisplay))
	}

	fmt.Println()
}
