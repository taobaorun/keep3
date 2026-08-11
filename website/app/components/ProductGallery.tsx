/* eslint-disable @next/next/no-img-element -- vinext serves these local assets directly. */
const assetBasePath = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

const captureGroups = [
  {
    key: "priorities",
    index: "01",
    label: "PRIORITIES",
    title: "重点",
    description: "一行提醒守住当前方向，需要回看时再展开全部上下文。",
    captures: [
      {
        state: "COMPACT",
        caption: "紧凑状态只留下当前重点，让主线一直在视线边缘。",
        src: "/product-gallery/priority-compact.webp",
        alt: "Keep3 紧凑重点界面，显示第一项重点 AD-Harness",
      },
      {
        state: "EXPANDED",
        caption: "主动停留后展开完整重点，并保留前后切换。",
        src: "/product-gallery/priority-expanded.webp",
        alt: "Keep3 展开重点界面，显示第三项重点 AgentRuntime 和切换控件",
      },
    ],
  },
  {
    key: "media",
    index: "02",
    label: "MEDIA",
    title: "媒体",
    description: "播放开始时自然接管同一位置，从曲目信息延伸到完整控制。",
    captures: [
      {
        state: "COMPACT",
        caption: "紧凑状态轻轻提示正在播放，不打断眼前工作。",
        src: "/product-gallery/media-compact.webp",
        alt: "Keep3 紧凑媒体界面，显示专辑封面、歌曲信息和播放波形",
      },
      {
        state: "EXPANDED",
        caption: "展开后集中呈现封面、进度与上一首、暂停、下一首控制。",
        src: "/product-gallery/media-expanded.webp",
        alt: "Keep3 展开媒体界面，显示李健八月照相馆的封面、进度和播放控制",
      },
    ],
  },
] as const;

export function ProductGallery() {
  return (
    <section
      className="product-gallery"
      id="product-gallery"
      aria-labelledby="product-gallery-title"
    >
      <div className="gallery-intro">
        <p className="eyebrow">REAL PRODUCT MOMENTS</p>
        <h2 id="product-gallery-title">从一行提示，到完整控制。</h2>
        <p>
          两种内容，四个真实状态。Keep3 始终在同一位置完成收起与展开，
          不让界面本身成为新的干扰。
        </p>
      </div>

      <div className="capture-groups">
        {captureGroups.map((group) => (
          <article className="capture-group" key={group.key}>
            <header className="capture-group-heading">
              <span>{group.index}</span>
              <div>
                <p>{group.label}</p>
                <h3>{group.title}</h3>
                <p>{group.description}</p>
              </div>
            </header>

            <div className="capture-sequence">
              {group.captures.map((capture) => (
                <figure className="capture-frame" key={capture.state}>
                  <img
                    src={`${assetBasePath}${capture.src}`}
                    width={1536}
                    height={1024}
                    loading="lazy"
                    decoding="async"
                    alt={capture.alt}
                  />
                  <figcaption>
                    <span>{capture.state}</span>
                    <p>{capture.caption}</p>
                  </figcaption>
                </figure>
              ))}
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}
