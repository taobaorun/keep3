type InstallNoticeProps = {
  method: "dmg" | "homebrew";
};

export function InstallNotice({ method }: InstallNoticeProps) {
  const message =
    method === "dmg"
      ? "未经过 Apple 公证，需要手动确认 →"
      : "安装后仍需完成一次 macOS 确认 →";

  return (
    <a
      className={`install-notice${method === "homebrew" ? " install-notice-dark" : ""}`}
      href="#first-launch-guide"
    >
      <span>首次打开说明</span>
      <strong>{message}</strong>
    </a>
  );
}

export function UnsignedFirstLaunchGuide() {
  return (
    <aside
      className="first-launch-guide"
      id="first-launch-guide"
      aria-labelledby="first-launch-guide-title"
    >
      <div className="first-launch-guide-heading">
        <p className="detail-label">FIRST LAUNCH GUIDE</p>
        <h3 id="first-launch-guide-title">第一次打开，只需手动确认一次。</h3>
        <p>
          当前版本未经过 Apple 公证，所以 Keep3 无法在系统放行前显示自己的引导。
          请按下面的安全步骤打开，不需要关闭 Gatekeeper。
        </p>
      </div>
      <ol>
        <li>
          <span>01</span>
          <div>
            <strong>打开“应用程序”</strong>
            <p>DMG 用户先把 Keep3 拖进去；Homebrew 用户可直接在这里找到它。</p>
          </div>
        </li>
        <li>
          <span>02</span>
          <div>
            <strong>按住 Control 点击 Keep3</strong>
            <p>在快捷菜单中选择“打开”，再确认一次“打开”。</p>
          </div>
        </li>
        <li>
          <span>03</span>
          <div>
            <strong>如果仍被拦截</strong>
            <p>前往“系统设置 → 隐私与安全性”，点击“仍要打开”。</p>
          </div>
        </li>
      </ol>
      <div className="first-launch-guide-footer">
        <p>macOS 通常只要求确认一次，之后可以从“应用程序”正常启动和更新。</p>
        <a
          href="https://support.apple.com/102445"
          target="_blank"
          rel="noreferrer"
        >
          查看 Apple 官方说明 ↗
        </a>
      </div>
    </aside>
  );
}
