//go:build ios

package libhysteria

import (
	"runtime/debug"
	"sync"
	"time"
)

// iOS network extensions are limited to roughly 50 MB. Keep the Go heap small and return
// freed pages to the OS every second, like libXray does on iOS. GOOS=ios also covers tvOS.

const memoryLimitBytes = 40 << 20

var (
	memoryOnce sync.Once
	memoryStop chan struct{}
	memoryMu   sync.Mutex
)

func initMemory() {
	memoryOnce.Do(func() {
		debug.SetGCPercent(10)
		debug.SetMemoryLimit(memoryLimitBytes)
	})
	memoryMu.Lock()
	defer memoryMu.Unlock()
	if memoryStop != nil {
		return
	}
	stop := make(chan struct{})
	memoryStop = stop
	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				debug.FreeOSMemory()
			case <-stop:
				return
			}
		}
	}()
}

func stopMemory() {
	memoryMu.Lock()
	defer memoryMu.Unlock()
	if memoryStop != nil {
		close(memoryStop)
		memoryStop = nil
	}
	debug.FreeOSMemory()
}
