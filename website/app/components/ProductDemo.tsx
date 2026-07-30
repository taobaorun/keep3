"use client";

import { useState } from "react";

const modes = [
  {
    key: "priorities",
    label: "三件重点",
    index: "01",
    title: "重要的事，始终在视线边缘。",
    description:
      "最多保留三件重点，并指定其中一件为当前焦点。加权轮播让主线长期可见，其余事项只在必要时轻轻出现。",
  },
  {
    key: "media",
    label: "媒体",
    index: "02",
    title: "播放开始时，媒体自然接管。",
    description:
      "当前媒体会在同一块界面中显示封面、标题、进度与可用控制。暂停后仍可继续操作，左右手势切换曲目。",
  },
  {
    key: "calendar",
    label: "日历",
    index: "03",
    title: "下一场安排，恰好提前看见。",
    description:
      "主动开启日历后，Keep3 只读取未来 24 小时内的本地日程投影。没有账户、同步，也不保存事件副本。",
  },
] as const;

type ModeKey = (typeof modes)[number]["key"];

export function ProductDemo() {
  const [active, setActive] = useState<ModeKey>("priorities");
  const current = modes.find((mode) => mode.key === active) ?? modes[0];

  return (
    <div className="product-demo">
      <div className="demo-copy">
        <div className="demo-tabs" role="tablist" aria-label="选择 Keep3 核心能力">
          {modes.map((mode) => (
            <button
              key={mode.key}
              id={`tab-${mode.key}`}
              type="button"
              role="tab"
              aria-selected={active === mode.key}
              aria-controls="capability-panel"
              className={active === mode.key ? "active" : ""}
              onClick={() => setActive(mode.key)}
            >
              <span>{mode.index}</span>
              {mode.label}
            </button>
          ))}
        </div>
        <div
          className="demo-description"
          id="capability-panel"
          role="tabpanel"
          aria-labelledby={`tab-${active}`}
          tabIndex={0}
        >
          <span>{current.index} / 03</span>
          <h3>{current.title}</h3>
          <p>{current.description}</p>
        </div>
      </div>

      <div className="demo-stage">
        <div className="demo-desktop">
          <div className="demo-menu">
            <span>Keep3</span>
            <span>Wed 9:41</span>
          </div>
          <div className="demo-backdrop">
            <div className="demo-window">
              <span />
              <span />
              <span />
              <div />
            </div>
          </div>
          <div className={`demo-surface demo-surface-${active}`}>
            <span className="demo-notch" aria-hidden="true" />
            {active === "priorities" && (
              <div className="priority-demo">
                <div className="surface-header">
                  <span className="focus-dot" />
                  <small>当前重点 · 1 / 3</small>
                </div>
                <strong>让 Keep3 的核心能力一眼可懂</strong>
                <p>精简首屏文案，确认三种顶部界面的层级。</p>
                <div className="demo-subitems">
                  <span>品牌表达保持安静、克制</span>
                  <span>移动端依然保留产品质感</span>
                </div>
              </div>
            )}
            {active === "media" && (
              <div className="media-demo">
                <div className="album-art" aria-hidden="true">
                  <span />
                </div>
                <div className="track-copy">
                  <small>NOW PLAYING</small>
                  <strong>Weightless Focus</strong>
                  <span>Keep3 Sessions</span>
                  <div className="track-progress">
                    <i />
                  </div>
                  <div className="track-controls" aria-hidden="true">
                    <span>↶</span>
                    <span className="play-control">Ⅱ</span>
                    <span>↷</span>
                  </div>
                </div>
              </div>
            )}
            {active === "calendar" && (
              <div className="calendar-demo">
                <div className="calendar-date" aria-hidden="true">
                  <span>JUL</span>
                  <strong>29</strong>
                </div>
                <div>
                  <small>NEXT EVENT · 14:30</small>
                  <strong>Keep3 产品体验回顾</strong>
                  <p>还有 26 分钟 · 45 分钟</p>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
