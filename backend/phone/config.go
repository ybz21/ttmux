// config.go：手机后端目标的可配置项，持久化到 <dataDir>/phone-config.json，由设置页管理。
//
// 三种模式(对应设置页「手机/Android」)：
//
//	local   本地 redroid —— 同机容器，默认 adb 地址 localhost:5555
//	remote  远程 redroid —— 另一台机器(如 ARM 主机/Jetson)上的 redroid，填它的 adb 地址 host:port
//	device  真机 —— 无线调试填 host:port；USB 调试填 adb serial（留空=默认单设备）
//
// host:port 形式的地址在 Ensure 时会先 `adb connect`（幂等），之后用它当 -s 目标。
package phone

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"sync"
)

type Config struct {
	Mode    string `json:"mode"`    // local | remote | device | ios
	Address string `json:"address"` // adb 地址 host:port / USB serial；ios 模式下为模拟器 UDID（空=booted）
	// Resolution: 设备显示分辨率预设(adb wm size/density)，仅 Android 有效。
	// "" / "phone" = 原生(reset)；其余见 ResolutionPresets。设置页可选。
	Resolution string `json:"resolution,omitempty"`
}

// resPreset 是一组 adb wm size/density 取值。
type resPreset struct{ Size, Density string }

// ResolutionPresets: 设置页可选的设备分辨率档(平板等)。
// key 不在表里(含 "" / "phone")= 还原设备原生分辨率。
var ResolutionPresets = map[string]resPreset{
	"tablet":       {Size: "1200x1920", Density: "240"}, // 10" 平板竖屏
	"tablet-land":  {Size: "1920x1200", Density: "240"}, // 10" 平板横屏
	"tablet-large": {Size: "2560x1600", Density: "280"}, // 大平板
}

var cfgStore struct {
	mu   sync.Mutex
	file string
	cur  Config
}

// 默认：macOS 上默认 iOS 模拟器，其它默认本地 redroid。
func defaultConfig() Config {
	if runtime.GOOS == "darwin" {
		return Config{Mode: "ios", Address: ""}
	}
	return Config{Mode: "local", Address: "localhost:5555"}
}

// InitConfig 设定配置文件路径并加载已存配置，由 server.New 用 dataDir 调一次。
func InitConfig(dataDir string) {
	cfgStore.mu.Lock()
	defer cfgStore.mu.Unlock()
	cfgStore.cur = defaultConfig()
	if dataDir == "" {
		return
	}
	_ = os.MkdirAll(dataDir, 0o755)
	cfgStore.file = filepath.Join(dataDir, "phone-config.json")
	if b, err := os.ReadFile(cfgStore.file); err == nil {
		var c Config
		if json.Unmarshal(b, &c) == nil && c.Mode != "" {
			cfgStore.cur = c
		}
	}
}

func getConfig() Config {
	cfgStore.mu.Lock()
	defer cfgStore.mu.Unlock()
	return cfgStore.cur
}

func setConfig(c Config) {
	if c.Mode == "" {
		c.Mode = "local"
	}
	cfgStore.mu.Lock()
	cfgStore.cur = c
	f := cfgStore.file
	cfgStore.mu.Unlock()
	if f != "" {
		if b, err := json.MarshalIndent(c, "", "  "); err == nil {
			_ = os.WriteFile(f, b, 0o600)
		}
	}
}
