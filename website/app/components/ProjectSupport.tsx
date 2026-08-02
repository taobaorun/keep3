const afdianPlanUrl = "https://afdian.com/a/taobaorun/plan";

export function ProjectSupport() {
  return (
    <section
      className="support-section"
      id="support"
      aria-labelledby="support-title"
    >
      <div className="support-copy">
        <p className="eyebrow">SUPPORT INDEPENDENT SOFTWARE</p>
        <h2 id="support-title">
          如果 Keep3 对你有帮助，
          <span>支持它持续开发。</span>
        </h2>
        <p>
          你的支持会用于持续开发、签名公证和发布维护，让每一次更新更稳定、更长久。
          Keep3 会继续保持免费、开源和本地优先。
        </p>
      </div>

      <div className="support-card">
        <div className="support-card-topline">
          <span>VOLUNTARY SUPPORT</span>
          <span aria-hidden="true">01</span>
        </div>
        <p className="support-statement">
          支持完全自愿。无论是否支持，都不会改变 Keep3 的下载、更新或任何功能。
        </p>
        <a
          className="support-button"
          href={afdianPlanUrl}
          target="_blank"
          rel="noreferrer"
        >
          在爱发电支持 Keep3
          <span aria-hidden="true">↗</span>
        </a>
      </div>
    </section>
  );
}
