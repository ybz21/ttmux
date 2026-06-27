// handlers.go：/api/phone/* 的 REST 处理器（健康/App/按键/UI 结构）。
// 画面与连续输入走 WS（screencast.go）；这些是离散的一次性操作。
package phone

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// Health 返回设备可用性 + 平台 + 目标标识。连不上时前端据 Error 显示原因。
func Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"data": Current().Health()})
}

// Apps 列出可启动应用。
func Apps(c *gin.Context) {
	apps, err := Current().Apps()
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": apps})
}

// Launch 启动指定 App（路径参数 id = 包名/bundleId）。
func Launch(c *gin.Context) {
	if err := Current().Launch(c.Param("id")); err != nil {
		c.JSON(http.StatusOK, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"ok": true}})
}

// Key 发系统键（body: {name: back|home|enter|recents|power}）。
func Key(c *gin.Context) {
	var body struct {
		Name string `json:"name"`
	}
	_ = c.ShouldBindJSON(&body)
	if err := Current().Key(body.Name); err != nil {
		c.JSON(http.StatusOK, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"ok": true}})
}

// GetConfig 返回当前手机后端配置（模式 + 地址）。
func GetConfig(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"data": getConfig()})
}

// SetConfig 保存配置并立即尝试连接，回显健康状态（设置页「保存并连接」）。
func SetConfig(c *gin.Context) {
	var body Config
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusOK, gin.H{"error": "无效配置"})
		return
	}
	setConfig(body)
	dev := Current()
	_ = dev.Ensure()
	// 非 iOS(= Android)按设置的分辨率预设改设备显示(wm size/density)。
	if getConfig().Mode != "ios" {
		_ = androidImpl.SetResolution(getConfig().Resolution)
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"config": getConfig(), "health": dev.Health()}})
}

// Connect 按当前配置重连并回健康（设置页「测试连接」）。
func Connect(c *gin.Context) {
	_ = Current().Ensure()
	c.JSON(http.StatusOK, gin.H{"data": Current().Health()})
}

// UI 返回当前屏幕的元素结构（给 agent 看结构算坐标）。
func UI(c *gin.Context) {
	els, err := Current().UIDump()
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": els})
}
