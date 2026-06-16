import React from 'react'
import { createRoot } from 'react-dom/client'
import { ConfigProvider, theme, App as AntApp } from 'antd'
import zhCN from 'antd/locale/zh_CN'
import App from './App'
import './index.css'

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <ConfigProvider
      locale={zhCN}
      theme={{
        algorithm: theme.darkAlgorithm,
        token: {
          colorPrimary: '#58a6ff',
          // 圆角分级：小控件收一点、卡片/弹层更柔
          borderRadius: 8,
          borderRadiusLG: 12,
          borderRadiusSM: 6,
          // 精修字体栈（与 index.css 一致）+ 略松行高，排版更透气
          fontFamily: "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', Roboto, Helvetica, Arial, sans-serif",
          fontSize: 14,
          lineHeight: 1.6,
          // 统一深黑主题
          colorBgBase: '#0d1117',
          colorBgContainer: '#161b22',
          colorBgElevated: '#1b222b', // 弹层/模态略提亮，拉开层次
          colorBgLayout: '#0d1117',
          colorBorder: '#2a313a',     // 主边框收敛，少一分生硬
          colorBorderSecondary: '#21262d',
          boxShadowSecondary: '0 8px 24px rgba(1,4,9,0.5)',
          wireframe: false,
        },
        components: {
          Layout: { siderBg: '#0d1117', headerBg: '#161b22', bodyBg: '#0d1117' },
          Menu: {
            darkItemBg: 'transparent',
            darkItemSelectedBg: 'rgba(88,166,255,0.16)',
            darkItemSelectedColor: '#58a6ff',
            darkItemHoverBg: 'rgba(255,255,255,0.04)',
            itemBorderRadius: 8,
            itemHeight: 42,
            itemMarginInline: 8,
          },
          // 卡片：标题更稳、内距更舒展
          Card: { borderRadiusLG: 12, paddingLG: 18, headerFontSize: 15 },
          // 按钮：去掉默认投影更干净，字重略加
          Button: { fontWeight: 500, primaryShadow: 'none', defaultShadow: 'none', dangerShadow: 'none' },
          Modal: { borderRadiusLG: 14, contentBg: '#161b22', headerBg: 'transparent' },
          // 分段控件选中态用主色，醒目克制
          Segmented: { borderRadius: 8, itemSelectedBg: '#1f6feb', itemSelectedColor: '#fff' },
          Tag: { borderRadiusSM: 6 },
          Tooltip: { borderRadius: 8 },
        },
      }}
    >
      <AntApp>
        <App />
      </AntApp>
    </ConfigProvider>
  </React.StrictMode>,
)
