/**
 * 본문 이미지 확대 보기(라이트박스)
 * - 본문(.content) 영역의 <img> 클릭 시 화면 전체로 확대한다.
 * - 동적으로 삽입되는 콘텐츠도 지원하도록 이벤트 위임을 사용한다.
 */
;(function () {
  const OVERLAY_ID = 'image-lightbox'
  const CONTENT_SELECTOR = '.content'

  let overlay = null
  let stage = null
  let image = null
  let lastFocused = null

  function createOverlay() {
    const el = document.createElement('div')
    el.id = OVERLAY_ID
    el.className = 'image-lightbox'
    el.setAttribute('role', 'dialog')
    el.setAttribute('aria-modal', 'true')
    el.setAttribute('aria-label', '이미지 확대 보기')
    el.innerHTML = `
      <button type="button" class="image-lightbox-close" aria-label="닫기">&times;</button>
      <div class="image-lightbox-stage">
        <img class="image-lightbox-img" alt="" />
      </div>
      <p class="image-lightbox-hint">클릭하면 원본 크기로 전환된다. ESC 키로 닫는다.</p>
    `

    stage = el.querySelector('.image-lightbox-stage')
    image = el.querySelector('.image-lightbox-img')

    el.querySelector('.image-lightbox-close').addEventListener('click', close)

    // 배경(스테이지 여백) 클릭 시 닫기, 이미지 클릭 시 원본 크기 전환
    el.addEventListener('click', (event) => {
      if (event.target === image) {
        toggleZoom()
        return
      }
      if (event.target === el || event.target === stage) {
        close()
      }
    })

    document.body.appendChild(el)

    return el
  }

  function ensureOverlay() {
    if (!overlay || !document.body.contains(overlay)) {
      overlay = createOverlay()
    }
    return overlay
  }

  function open(sourceImage) {
    ensureOverlay()

    lastFocused = document.activeElement

    image.src = sourceImage.currentSrc || sourceImage.src
    image.alt = sourceImage.alt || ''
    overlay.classList.remove('is-zoomed')
    overlay.classList.add('is-open')
    stage.scrollTop = 0
    stage.scrollLeft = 0
    document.body.classList.add('image-lightbox-open')

    overlay.querySelector('.image-lightbox-close').focus()
  }

  function close() {
    if (!overlay || !overlay.classList.contains('is-open')) return

    overlay.classList.remove('is-open', 'is-zoomed')
    document.body.classList.remove('image-lightbox-open')
    image.removeAttribute('src')

    if (lastFocused && typeof lastFocused.focus === 'function') {
      lastFocused.focus()
    }
    lastFocused = null
  }

  function toggleZoom() {
    if (!overlay) return

    const willZoom = !overlay.classList.contains('is-zoomed')
    overlay.classList.toggle('is-zoomed', willZoom)

    if (willZoom) {
      // 확대 시 이미지 중앙이 보이도록 스크롤을 맞춘다.
      stage.scrollLeft = (stage.scrollWidth - stage.clientWidth) / 2
      stage.scrollTop = (stage.scrollHeight - stage.clientHeight) / 2
    } else {
      stage.scrollTop = 0
      stage.scrollLeft = 0
    }
  }

  function isZoomableImage(target) {
    if (!target || target.tagName !== 'IMG') return false
    if (target.closest(`#${OVERLAY_ID}`)) return false
    if (!target.closest(CONTENT_SELECTOR)) return false
    if (target.closest('a')) return false
    if (target.dataset.noZoom !== undefined) return false
    return true
  }

  document.addEventListener('click', (event) => {
    const target = event.target
    if (!isZoomableImage(target)) return

    event.preventDefault()
    open(target)
  })

  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return
    close()
  })
})()
