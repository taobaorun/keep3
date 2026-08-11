/* eslint-disable @next/next/no-img-element -- vinext serves these local assets directly. */
import { ProductDemo } from "./components/ProductDemo";
import { ProductDownload } from "./components/ProductDownload";
import { ProductGallery } from "./components/ProductGallery";
import { ProjectSupport } from "./components/ProjectSupport";

const assetBasePath = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

export default function Home() {
  return (
    <>
      <header className="site-header">
        <a className="brand" href="#top" aria-label="Keep3 首页">
          <img
            className="brand-icon"
            src={`${assetBasePath}/keep3-app-icon.png`}
            width={40}
            height={40}
            alt=""
          />
          <span>Keep3</span>
        </a>
        <nav className="nav-links" aria-label="主导航">
          <a href="#capabilities">核心能力</a>
          <a href="#quiet">设计原则</a>
          <a href="#support">支持</a>
          <a href="#about">关于 Keep3</a>
          <a className="nav-cta" href="#download">
            下载
          </a>
        </nav>
      </header>

      <main id="top">
        <section className="hero">
          <div className="hero-copy">
            <p className="eyebrow">KEEP THREE THINGS IN SIGHT.</p>
            <h1>
              把最重要的
              <span>三件事</span>
              ，留在视线里。
            </h1>
            <p className="hero-lede">
              Keep3 是一块安静的原生 Mac 顶部界面。它不管理你的任务，
              只在注意力被拉走之后，帮你看一眼就找回原本要做的事。
            </p>
            <div className="hero-actions">
              <a className="primary-button" href="#download">
                下载 Keep3 <span aria-hidden="true">↓</span>
              </a>
              <a className="text-link" href="#capabilities">
                看看它如何工作
              </a>
              <span className="platform-note">免费 · 开源 · 本地优先</span>
            </div>
          </div>

          <div className="hero-object" aria-label="Keep3 顶部重点界面示意">
            <div className="app-icon-halo">
              <img
                className="hero-icon"
                src={`${assetBasePath}/keep3-app-icon.png`}
                width={320}
                height={320}
                alt="Keep3 应用图标"
              />
            </div>
            <div className="desktop-preview">
              <div className="desktop-menu">
                <span>9:41</span>
                <span>⌁ &nbsp; ◐ &nbsp; 100%</span>
              </div>
              <div className="window-ghost window-ghost-left" />
              <div className="window-ghost window-ghost-right" />
              <div className="notch-surface">
                <span className="notch-cutout" aria-hidden="true" />
                <span className="focus-dot" aria-hidden="true" />
                <strong>完成 Keep3 产品页</strong>
                <span className="surface-count">1 / 3</span>
              </div>
            </div>
          </div>
        </section>

        <section className="manifesto" aria-labelledby="manifesto-title">
          <p>世界上暂时只有三件重要的事。</p>
          <h2 id="manifesto-title">
            不是更多提醒，
            <br />
            是更少的注意力分叉。
          </h2>
        </section>

        <section className="capabilities" id="capabilities">
          <div className="section-heading">
            <p className="eyebrow">CORE CAPABILITIES</p>
            <h2>一个位置，守住你的工作上下文。</h2>
            <p>
              重点、正在播放的媒体和下一场日程，共用屏幕顶部的一块安静界面。
              只有当你需要时，它才展开更多。
            </p>
          </div>
          <ProductDemo />
          <ProductGallery />
        </section>

        <section className="focus-system" aria-labelledby="focus-system-title">
          <div className="focus-system-intro">
            <p className="eyebrow">THE KEEP3 METHOD</p>
            <h2 id="focus-system-title">三件事，但每次只守住一件。</h2>
          </div>
          <div className="system-steps">
            <article>
              <span className="step-number">01</span>
              <h3>最多三件重点</h3>
              <p>
                亲自写下今天真正重要的事。没有无限清单，也没有让你继续整理的诱惑。
              </p>
            </article>
            <article>
              <span className="step-number">02</span>
              <h3>指定当前焦点</h3>
              <p>
                当前重点占据大部分展示时间；另外两件低频出现，保留全局感但不抢注意力。
              </p>
            </article>
            <article>
              <span className="step-number">03</span>
              <h3>抬眼就能回来</h3>
              <p>
                被消息或临时需求打断后，不必打开任务管理器。看向屏幕顶部，继续原来的事。
              </p>
            </article>
          </div>
        </section>

        <section className="quiet-section" id="quiet">
          <div className="quiet-copy">
            <p className="eyebrow eyebrow-light">QUIET BY DEFAULT</p>
            <h2>一直都在，几乎感觉不到。</h2>
            <p>
              快速经过不会误触，主动停留才会展开；界面不抢键盘焦点，
              也不会用通知、红点或完成率评判你。
            </p>
          </div>
          <div className="quiet-principles">
            <div>
              <strong>0</strong>
              <span>账户</span>
            </div>
            <div>
              <strong>0</strong>
              <span>云端同步</span>
            </div>
            <div>
              <strong>0</strong>
              <span>分析追踪</span>
            </div>
            <p>
              重点内容保存在本机。日历默认关闭，只有你主动开启后才请求系统权限。
            </p>
          </div>
        </section>

        <section className="depth-section" aria-labelledby="depth-title">
          <div className="depth-copy">
            <p className="eyebrow">ONE SURFACE, THREE LEVELS</p>
            <h2 id="depth-title">从一行提示，到完整上下文。</h2>
            <p>
              Keep3 贴合有刘海和无刘海的 Mac 屏幕。紧凑状态只留一行信息，
              需要操作时再自然展开，离开后回到安静状态。
            </p>
          </div>
          <div className="depth-levels" aria-label="Keep3 的三层界面状态">
            <div className="depth-level hardware-level">
              <span>硬件对齐</span>
            </div>
            <div className="depth-level compact-level">
              <span className="mini-dot" />
              <strong>发布 Keep3 网站</strong>
              <span>紧凑</span>
            </div>
            <div className="depth-level expanded-level">
              <small>当前重点 · 1 / 3</small>
              <strong>发布 Keep3 网站</strong>
              <p>检查移动端版式，确认产品能力表达清晰。</p>
              <div>
                <span>← 上一项</span>
                <span>下一项 →</span>
              </div>
            </div>
          </div>
        </section>

        <ProductDownload />

        <ProjectSupport />

        <section className="closing" id="about">
          <img
            src={`${assetBasePath}/keep3-app-icon.png`}
            width={88}
            height={88}
            alt=""
          />
          <p className="eyebrow">KEEP3 FOR MAC</p>
          <h2>少一点管理，多一点看见。</h2>
          <p>
            Keep3 是一款免费、开源的原生 macOS 应用。
            它的目标很简单：让你每天都愿意把真正重要的事留在屏幕顶部。
          </p>
          <a className="status-pill" href="#download">
            获取 Keep3 for Mac
          </a>
        </section>
      </main>

      <footer>
        <a className="brand footer-brand" href="#top">
          <img
            src={`${assetBasePath}/keep3-app-icon.png`}
            width={32}
            height={32}
            alt=""
          />
          <span>Keep3</span>
        </a>
        <p>Keep three things in sight.</p>
        <p>© 2026 Keep3</p>
      </footer>
    </>
  );
}
