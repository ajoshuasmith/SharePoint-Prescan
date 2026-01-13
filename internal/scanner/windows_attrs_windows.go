//go:build windows

package scanner

import "golang.org/x/sys/windows"

func isHiddenWindows(path string) bool {
	attrs, err := windows.GetFileAttributes(windows.StringToUTF16Ptr(path))
	if err != nil {
		return false
	}
	return attrs&windows.FILE_ATTRIBUTE_HIDDEN != 0
}

func isSystemWindows(path string) bool {
	attrs, err := windows.GetFileAttributes(windows.StringToUTF16Ptr(path))
	if err != nil {
		return false
	}
	return attrs&windows.FILE_ATTRIBUTE_SYSTEM != 0
}
