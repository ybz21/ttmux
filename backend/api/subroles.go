// subroles.go：细分角色注册表（产品/架构/工程/测试…），见
// docs/design/蜂群成员角色模型设计.md §3。后端持 key→label/icon 的源头，
// 供 prompt 渲染（取 label + 角色片段文件名）与 GET /api/swarm/subroles（喂前端下拉）。
// 前端另持同 key 的图标/配色；CLI 持轻量 SubroleNorm。三处以 key 对齐。
package api

import (
	"strings"

	"github.com/gin-gonic/gin"
)

// Subrole 是注册表一项。Key 同时是 prompts/roles/<key>.md 的文件名。
type Subrole struct {
	Key   string `json:"key"`
	Label string `json:"label"`
	Icon  string `json:"icon"`
}

// subroleRegistry 是固定枚举（未命中即「自定义」，原样保留，走通用处理）。
var subroleRegistry = []Subrole{
	{"pm", "产品经理", "🧭"},
	{"architect", "架构师", "🏛"},
	{"frontend", "前端工程师", "🎨"},
	{"backend", "后端工程师", "⚙️"},
	{"fullstack", "全栈工程师", "🛠"},
	{"qa", "测试工程师", "🧪"},
	{"designer", "设计师", "✏️"},
	{"reviewer", "代码审查", "🔍"},
	{"devops", "运维", "🚢"},
	{"docs", "文档", "📝"},
	{"commander", "总指挥", "◆"},
}

// subroleAliases 把中英文别名归一到 key（与 CLI 的 SubroleNorm 对齐）。
var subroleAliases = map[string]string{
	"pm": "pm", "product": "pm", "产品": "pm", "产品经理": "pm",
	"architect": "architect", "arch": "architect", "架构": "architect", "架构师": "architect",
	"frontend": "frontend", "fe": "frontend", "front": "frontend", "前端": "frontend", "前端工程师": "frontend",
	"backend": "backend", "be": "backend", "back": "backend", "后端": "backend", "后端工程师": "backend",
	"fullstack": "fullstack", "full": "fullstack", "全栈": "fullstack", "全栈工程师": "fullstack",
	"qa": "qa", "test": "qa", "tester": "qa", "测试": "qa", "测试工程师": "qa",
	"designer": "designer", "design": "designer", "设计": "designer", "设计师": "designer",
	"reviewer": "reviewer", "review": "reviewer", "审查": "reviewer", "代码审查": "reviewer",
	"devops": "devops", "ops": "devops", "运维": "devops",
	"docs": "docs", "doc": "docs", "writer": "docs", "文档": "docs",
	"commander": "commander", "leader": "commander", "master": "commander", "指挥": "commander", "总指挥": "commander",
}

// subroleNorm 归一到 key；未识别保留原串（自定义）。
func subroleNorm(s string) string {
	if k, ok := subroleAliases[strings.ToLower(strings.TrimSpace(s))]; ok {
		return k
	}
	return strings.TrimSpace(s)
}

// subroleLabel 返回 key 对应中文 label；自定义/空则原样返回（空→空）。
func subroleLabel(key string) string {
	for _, r := range subroleRegistry {
		if r.Key == key {
			return r.Label
		}
	}
	return key
}

// GET /api/swarm/subroles —— 细分角色注册表，供前端「加成员」下拉。
func (a *API) SwarmSubroles(c *gin.Context) {
	c.JSON(200, subroleRegistry)
}
