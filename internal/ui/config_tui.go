package ui

import (
	"fmt"
	"os"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ConfigResult holds the values collected from the interactive setup.
type ConfigResult struct {
	Path        string
	Destination string
	Output      string
	Canceled    bool
}

type configModel struct {
	inputs     []textinput.Model
	focusIndex int
	done       bool
	canceled   bool
	errMsg     string
	width      int
}

func RunConfigTUI(defaultPath, defaultDestination, defaultOutput string) (ConfigResult, error) {
	model := newConfigModel(defaultPath, defaultDestination, defaultOutput)
	program := tea.NewProgram(model, tea.WithAltScreen())
	finalModel, err := program.Run()
	if err != nil {
		return ConfigResult{}, err
	}

	m, ok := finalModel.(configModel)
	if !ok {
		return ConfigResult{}, fmt.Errorf("unexpected TUI model")
	}

	return ConfigResult{
		Path:        strings.TrimSpace(m.inputs[0].Value()),
		Destination: strings.TrimSpace(m.inputs[1].Value()),
		Output:      strings.TrimSpace(m.inputs[2].Value()),
		Canceled:    m.canceled,
	}, nil
}

func newConfigModel(defaultPath, defaultDestination, defaultOutput string) configModel {
	inputs := make([]textinput.Model, 3)

	pathInput := textinput.New()
	pathInput.Prompt = "Path: "
	pathInput.CharLimit = 2048
	pathInput.SetValue(defaultPath)
	pathInput.Focus()

	destinationInput := textinput.New()
	destinationInput.Prompt = "Destination: "
	destinationInput.CharLimit = 2048
	destinationInput.SetValue(defaultDestination)

	outputInput := textinput.New()
	outputInput.Prompt = "Output: "
	outputInput.CharLimit = 2048
	outputInput.SetValue(defaultOutput)

	inputs[0] = pathInput
	inputs[1] = destinationInput
	inputs[2] = outputInput

	m := configModel{
		inputs:     inputs,
		focusIndex: 0,
		width:      80,
	}
	m.applyFocus()

	return m
}

func (m configModel) Init() tea.Cmd {
	return nil
}

func (m configModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "esc":
			m.canceled = true
			return m, tea.Quit
		case "tab", "shift+tab", "up", "down":
			m.moveFocus(msg.String())
			return m, nil
		case "enter":
			if m.focusIndex < len(m.inputs)-1 {
				m.focusIndex++
				m.errMsg = ""
				m.applyFocus()
				return m, nil
			}

			if errMsg := m.validate(); errMsg != "" {
				m.errMsg = errMsg
				m.focusIndex = 0
				m.applyFocus()
				return m, nil
			}

			m.done = true
			return m, tea.Quit
		}
	}

	var cmd tea.Cmd
	m.inputs[m.focusIndex], cmd = m.inputs[m.focusIndex].Update(msg)
	return m, cmd
}

func (m configModel) View() string {
	if m.done {
		return ""
	}

	var b strings.Builder
	title := titleStyle.Render("Interactive Setup")
	b.WriteString(title)
	b.WriteString("\n\n")

	formWidth := m.width - 4
	if formWidth < 40 {
		formWidth = 40
	}

	var form strings.Builder
	form.WriteString(m.inputs[0].View())
	form.WriteString("\n")
	form.WriteString(m.inputs[1].View())
	form.WriteString("\n")
	form.WriteString(m.inputs[2].View())

	b.WriteString(boxStyle.Width(formWidth).Render(form.String()))

	if m.errMsg != "" {
		errorStyle := lipgloss.NewStyle().Foreground(errorColor).Bold(true)
		b.WriteString("\n\n")
		b.WriteString(errorStyle.Render(m.errMsg))
	}

	b.WriteString("\n\n")
	b.WriteString(subtleStyle.Render("Tab to move, Enter to start, Ctrl+C to cancel"))

	return b.String()
}

func (m *configModel) moveFocus(key string) {
	switch key {
	case "shift+tab", "up":
		m.focusIndex--
	default:
		m.focusIndex++
	}

	if m.focusIndex > len(m.inputs)-1 {
		m.focusIndex = 0
	}
	if m.focusIndex < 0 {
		m.focusIndex = len(m.inputs) - 1
	}

	m.errMsg = ""
	m.applyFocus()
}

func (m *configModel) applyFocus() {
	focused := lipgloss.NewStyle().Foreground(accentColor)
	blurred := lipgloss.NewStyle().Foreground(dimTextColor)

	for i := range m.inputs {
		if i == m.focusIndex {
			m.inputs[i].Focus()
			m.inputs[i].PromptStyle = focused
			m.inputs[i].TextStyle = focused
		} else {
			m.inputs[i].Blur()
			m.inputs[i].PromptStyle = blurred
			m.inputs[i].TextStyle = blurred
		}
	}
}

func (m configModel) validate() string {
	path := strings.TrimSpace(m.inputs[0].Value())
	if path == "" {
		return "Path is required."
	}
	if _, err := os.Stat(path); err != nil {
		return fmt.Sprintf("Path not found: %s", path)
	}
	return ""
}
