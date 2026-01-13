package scanner

import (
	"context"
	"io/fs"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/ajoshuasmith/sharepoint-prescan/internal/models"
)

// Scanner performs file system scanning
type Scanner struct {
	rootPath       string
	excludeFolders map[string]bool
	maxItems       int64
	workerCount    int
	progressChan   chan *models.ScanProgress
}

// NewScanner creates a new Scanner instance
func NewScanner(rootPath string, excludeFolders []string, maxItems int64) *Scanner {
	excludeMap := make(map[string]bool)
	for _, folder := range excludeFolders {
		excludeMap[strings.ToLower(folder)] = true
	}

	// Use CPU count for parallel processing
	workerCount := runtime.NumCPU()
	if workerCount > 8 {
		workerCount = 8 // Cap at 8 workers for diminishing returns
	}

	return &Scanner{
		rootPath:       rootPath,
		excludeFolders: excludeMap,
		maxItems:       maxItems,
		workerCount:    workerCount,
		progressChan:   make(chan *models.ScanProgress, 100),
	}
}

// Scan performs the file system scan and returns all items
func (s *Scanner) Scan(ctx context.Context) (<-chan *models.FileSystemItem, <-chan *models.ScanProgress, <-chan error) {
	itemsChan := make(chan *models.FileSystemItem, 1000)
	progressChan := make(chan *models.ScanProgress, 100)
	errChan := make(chan error, 1)

	go func() {
		defer close(itemsChan)
		defer close(progressChan)
		defer close(errChan)

		if err := s.scanDirectory(ctx, itemsChan, progressChan); err != nil {
			errChan <- err
		}
	}()

	return itemsChan, progressChan, errChan
}

func (s *Scanner) scanDirectory(ctx context.Context, itemsChan chan<- *models.FileSystemItem, progressChan chan<- *models.ScanProgress) error {
	var (
		itemsScanned int64
		filesScanned int64
		dirsScanned  int64
		bytesScanned int64
		mu           sync.Mutex
	)

	// Progress reporting ticker
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()

	var currentPath string
	go func() {
		for range ticker.C {
			mu.Lock()
			path := currentPath
			mu.Unlock()

			select {
			case progressChan <- &models.ScanProgress{
				ItemsScanned: atomic.LoadInt64(&itemsScanned),
				FilesScanned: atomic.LoadInt64(&filesScanned),
				DirsScanned:  atomic.LoadInt64(&dirsScanned),
				BytesScanned: atomic.LoadInt64(&bytesScanned),
				CurrentPath:  path,
			}:
			case <-ctx.Done():
				return
			}
		}
	}()

	// Walk the file system
	err := filepath.WalkDir(s.rootPath, func(path string, d fs.DirEntry, err error) error {
		// Check context cancellation
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		if err != nil {
			// Skip directories we can't access
			if d != nil && d.IsDir() {
				return filepath.SkipDir
			}
			return nil // Skip files with errors
		}

		// Update current path for progress
		mu.Lock()
		currentPath = path
		mu.Unlock()

		// Check if we should exclude this directory
		if d.IsDir() && s.shouldExcludeDir(d.Name()) {
			return filepath.SkipDir
		}

		// Check max items limit
		if s.maxItems > 0 && atomic.LoadInt64(&itemsScanned) >= s.maxItems {
			return filepath.SkipAll
		}

		// Get file info
		info, err := d.Info()
		if err != nil {
			return nil // Skip if we can't get info
		}

		// Create relative path
		relPath, err := filepath.Rel(s.rootPath, path)
		if err != nil {
			relPath = path
		}

		// Determine if hidden/system file
		isHidden := s.isHidden(d.Name(), path)
		isSystem := s.isSystem(path)

		// Create file system item
		item := &models.FileSystemItem{
			Path:         path,
			Name:         d.Name(),
			IsDir:        d.IsDir(),
			Size:         info.Size(),
			ModTime:      info.ModTime(),
			IsHidden:     isHidden,
			IsSystem:     isSystem,
			RelativePath: relPath,
		}

		// Send item to channel
		select {
		case itemsChan <- item:
			atomic.AddInt64(&itemsScanned, 1)
			if d.IsDir() {
				atomic.AddInt64(&dirsScanned, 1)
			} else {
				atomic.AddInt64(&filesScanned, 1)
				atomic.AddInt64(&bytesScanned, info.Size())
			}
		case <-ctx.Done():
			return ctx.Err()
		}

		return nil
	})

	// Send final progress update
	progressChan <- &models.ScanProgress{
		ItemsScanned: atomic.LoadInt64(&itemsScanned),
		FilesScanned: atomic.LoadInt64(&filesScanned),
		DirsScanned:  atomic.LoadInt64(&dirsScanned),
		BytesScanned: atomic.LoadInt64(&bytesScanned),
		CurrentPath:  "",
	}

	return err
}

func (s *Scanner) shouldExcludeDir(name string) bool {
	return s.excludeFolders[strings.ToLower(name)]
}

func (s *Scanner) isHidden(name, path string) bool {
	// Unix-style hidden files
	if strings.HasPrefix(name, ".") {
		return true
	}

	return isHiddenWindows(path)
}

func (s *Scanner) isSystem(path string) bool {
	return isSystemWindows(path)
}

// ParallelScan performs parallel scanning with multiple workers
func (s *Scanner) ParallelScan(ctx context.Context) (<-chan *models.FileSystemItem, <-chan *models.ScanProgress, <-chan error) {
	// For now, use the regular scan - parallel optimization can be added later
	// The bottleneck is typically disk I/O, not CPU
	return s.Scan(ctx)
}
