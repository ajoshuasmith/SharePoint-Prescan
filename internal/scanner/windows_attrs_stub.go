//go:build !windows

package scanner

func isHiddenWindows(path string) bool {
	return false
}

func isSystemWindows(path string) bool {
	return false
}
