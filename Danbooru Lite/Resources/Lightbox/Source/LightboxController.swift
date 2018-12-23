import Closures
import FontAwesome_swift
import Kingfisher
import Material
import Photos
import UIKit

public protocol LightboxControllerPageDelegate: class {

    func lightboxController(_ controller: LightboxController, didMoveToPage page: Int)
}

public protocol LightboxControllerDismissalDelegate: class {

    func lightboxControllerWillDismiss(_ controller: LightboxController)
}

public protocol LightboxControllerTouchDelegate: class {

    func lightboxController(_ controller: LightboxController, didTouch image: LightboxImage, at index: Int)
}

open class LightboxController: UIViewController {

    // MARK: - Internal views

    lazy var scrollView: UIScrollView = UIScrollView()

    lazy var effectView: UIVisualEffectView = {
        let effect = UIBlurEffect(style: .dark)
        let view = UIVisualEffectView(effect: effect)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        return view
    }()

    lazy var backgroundView: UIImageView = {
        let view = UIImageView()
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        return view
    }()

    // MARK: - Public views

    open fileprivate(set) lazy var headerView: HeaderView = {
        let view = HeaderView()
        view.delegate = self
        return view
    }()

    open fileprivate(set) lazy var footerView: FooterView = {
        let view = FooterView()
        view.delegate = self

        return view
    }()

    open fileprivate(set) lazy var overlayView: UIView = {
        let view = UIView(frame: CGRect.zero)
        let gradient = CAGradientLayer()
        view.alpha = 0

        return view
    }()

    // MARK: - Properties

    open fileprivate(set) var currentPage = 0 {
        didSet {
            currentPage = min(numberOfPages - 1, max(0, currentPage))
            footerView.updatePage(currentPage + 1, numberOfPages)
            footerView.updateText(pageViews[currentPage].image.text)

            if currentPage == numberOfPages - 1 {
                seen = true
            }

            pageDelegate?.lightboxController(self, didMoveToPage: currentPage)

            pageViews[currentPage].setImage()
            if let image = pageViews[currentPage].imageView.image, dynamicBackground {

                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.125) { [weak self] in
                    if self == nil {
                        return
                    }
                    self?.loadDynamicBackground(image)
                }
            }
        }
    }

    open var numberOfPages: Int {
        return pageViews.count
    }

    open var dynamicBackground: Bool = false {
        didSet {
            if dynamicBackground == true {
                effectView.frame = view.frame
                backgroundView.frame = effectView.frame
                view.insertSubview(effectView, at: 0)
                view.insertSubview(backgroundView, at: 0)
            } else {
                effectView.removeFromSuperview()
                backgroundView.removeFromSuperview()
            }
        }
    }

    open var spacing: CGFloat = 20 {
        didSet {
            configureLayout(view.bounds.size)
        }
    }

    open var images: [LightboxImage] {
        get {
            return pageViews.map { $0.image }
        }
        set(value) {
            configurePages(value)
        }
    }

    open weak var pageDelegate: LightboxControllerPageDelegate?
    open weak var dismissalDelegate: LightboxControllerDismissalDelegate?
    open weak var imageTouchDelegate: LightboxControllerTouchDelegate?
    open internal(set) var presented = false
    open fileprivate(set) var seen = false

    lazy var transitionManager: LightboxTransition = LightboxTransition()
    var pageViews = [PageView]()
    var statusBarHidden = false

    fileprivate let initialImages: [LightboxImage]
    fileprivate let initialPage: Int

    // MARK: - Initializers

    public init(images: [LightboxImage] = [], startIndex index: Int = 0) {
        initialImages = images
        initialPage = index
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public var booruPage: Int?

    // MARK: - View lifecycle

    deinit {
        print("Dinigcallsd")
        pageViews.forEach { $0.removeFromSuperview() }
        pageViews = []
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        statusBarHidden = UIApplication.shared.isStatusBarHidden

        scrollView.isPagingEnabled = false
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.decelerationRate = UIScrollViewDecelerationRateFast

        view.backgroundColor = UIColor.black
        transitionManager.lightboxController = self
        transitionManager.scrollView = scrollView
        transitioningDelegate = transitionManager

        [scrollView, overlayView, headerView, footerView].forEach { view.addSubview($0) }

        overlayView.addTapGesture { [weak self] tap in
            if self == nil {
                return
            }
            self?.overlayViewDidTap(tap)
        }

        configurePages(initialImages)
        currentPage = initialPage

        if let booruPage = booruPage {
            currentPage = booruPage
        }

        goTo(currentPage, animated: false)

        let button = IconButton(image: UIImage.fontAwesomeIcon(name: FontAwesome.download, textColor: UIColor.white, size: CGSize(width: 30, height: 30)), tintColor: .white)
        button.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(button)
        button.bottomAnchor.constraint(equalTo: footerView.bottomAnchor, constant: -20).isActive = true
        button.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -20).isActive = true

        button.onTap { [weak self] in
            if self == nil {
                return
            }
            if self!.currentPage <= self!.images.count, let image: URL = self!.images[self!.currentPage].imageURL {
                DownloadQueuer.instance.add(URL: image)
            }
        }

        let tag = IconButton(image: UIImage.fontAwesomeIcon(name: FontAwesome.tags, textColor: UIColor.white, size: CGSize(width: 30, height: 30)), tintColor: .white)
        tag.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(tag)
        tag.bottomAnchor.constraint(equalTo: footerView.bottomAnchor, constant: -20).isActive = true
        tag.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 20).isActive = true

        tag.onTap { [weak self] in
            if self == nil {
                return
            }
            if self!.currentPage <= self!.images.count {
                if self!.images[self!.currentPage].text == "" {
                    return
                }
                let actionSheet: UIAlertController = UIAlertController(title: nil, message: nil, preferredStyle: UIDevice.current.userInterfaceIdiom == UIUserInterfaceIdiom.pad ? .alert : UIAlertControllerStyle.actionSheet)
                for item in self!.images[self!.currentPage].text.components(separatedBy: " ") {
                    if item == "" {
                        return
                    }
                    let button = UIAlertAction(title: item, style: .default, handler: { (_) -> Void in
                        let controller = BooruNavigationController(rootViewController: SearchResultController(tag: item))
                        self?.present(controller, animated: true, completion: nil)
                    })
                    actionSheet.addAction(button)
                }

                let cancelButton = UIAlertAction(title: "Cancel", style: .cancel, handler: { (_) -> Void in
                    print("Cancel button tapped")
                })

                actionSheet.addAction(cancelButton)
                self?.present(actionSheet, animated: true, completion: nil)
            }
        }

    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !presented {
            presented = true
            configureLayout(view.bounds.size)
        }
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        scrollView.frame = view.bounds
        footerView.frame.size = CGSize(
            width: view.bounds.width,
            height: 100
        )

        footerView.frame.origin = CGPoint(
            x: 0,
            y: view.bounds.height - footerView.frame.height
        )

        headerView.frame = CGRect(
            x: 0,
            y: 16,
            width: view.bounds.width,
            height: 100
        )
    }

    open override var prefersStatusBarHidden: Bool {
        return LightboxConfig.hideStatusBar
    }

    // MARK: - Rotation

    open override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { [weak self] _ in
            if self == nil {
                return
            }
            self?.configureLayout(size)
        }, completion: nil)
    }

    // MARK: - Configuration

    func configurePages(_ images: [LightboxImage]) {
        pageViews.forEach { $0.removeFromSuperview() }
        pageViews = []

        for image in images {
            let pageView = PageView(image: image)
            pageView.pageViewDelegate = self

            scrollView.addSubview(pageView)
            pageViews.append(pageView)
        }

        configureLayout(view.bounds.size)
    }

    // MARK: - Pagination

    open func goTo(_ page: Int, animated: Bool = true) {
        guard page >= 0 && page < numberOfPages else {
            return
        }

        currentPage = page

        var offset = scrollView.contentOffset
        offset.x = CGFloat(page) * (scrollView.frame.width + spacing)

        let shouldAnimated = view.window != nil ? animated : false

        scrollView.setContentOffset(offset, animated: shouldAnimated)
    }

    open func next(_ animated: Bool = true) {
        goTo(currentPage + 1, animated: animated)
    }

    open func previous(_ animated: Bool = true) {
        goTo(currentPage - 1, animated: animated)
    }

    // MARK: - Actions

    @objc func overlayViewDidTap(_ tapGestureRecognizer: UITapGestureRecognizer) {
        footerView.expand(false)
    }

    // MARK: - Layout

    open func configureLayout(_ size: CGSize) {
        scrollView.frame.size = size
        scrollView.contentSize = CGSize(
            width: size.width * CGFloat(numberOfPages) + spacing * CGFloat(numberOfPages - 1),
            height: size.height
        )
        scrollView.contentOffset = CGPoint(x: CGFloat(currentPage) * (size.width + spacing), y: 0)

        for (index, pageView) in pageViews.enumerated() {
            var frame = scrollView.bounds
            frame.origin.x = (frame.width + spacing) * CGFloat(index)
            pageView.frame = frame
            pageView.configureLayout()
            if index != numberOfPages - 1 {
                pageView.frame.size.width += spacing
            }
        }

        [headerView, footerView].forEach { ($0 as AnyObject).configureLayout() }

        overlayView.frame = scrollView.frame
        overlayView.resizeGradientLayer()
    }

    fileprivate func loadDynamicBackground(_ image: UIImage) {
        backgroundView.image = image
        backgroundView.layer.add(CATransition(), forKey: kCATransitionFade)
    }

    func toggleControls(pageView: PageView?, visible: Bool, duration: TimeInterval = 0.1, delay: TimeInterval = 0) {
        let alpha: CGFloat = visible ? 1.0 : 0.0

        pageView?.playButton.isHidden = !visible

        UIView.animate(withDuration: duration, delay: delay, options: [], animations: { [weak self] in
            if self == nil {
                return
            }
            self?.headerView.alpha = alpha
            self?.footerView.alpha = alpha
            pageView?.playButton.alpha = alpha
        }, completion: nil)
    }
}

// MARK: - UIScrollViewDelegate

extension LightboxController: UIScrollViewDelegate {

    public func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        var speed: CGFloat = velocity.x < 0 ? -2 : 2

        if velocity.x == 0 {
            speed = 0
        }

        let pageWidth = scrollView.bounds.width + spacing
        var x = scrollView.contentOffset.x + speed * 60.0

        if speed > 0 {
            x = ceil(x / pageWidth) * pageWidth
        } else if speed < -0 {
            x = floor(x / pageWidth) * pageWidth
        } else {
            x = round(x / pageWidth) * pageWidth
        }

        targetContentOffset.pointee.x = x
        currentPage = Int(x / pageWidth)
    }
}

// MARK: - PageViewDelegate

extension LightboxController: PageViewDelegate {

    func remoteImageDidLoad(_ image: UIImage?, imageView: UIImageView) {
        guard let image = image, dynamicBackground else {
            return
        }

        let imageViewFrame = imageView.convert(imageView.frame, to: view)
        guard view.frame.intersects(imageViewFrame) else {
            return
        }

        loadDynamicBackground(image)
    }

    func pageViewDidZoom(_ pageView: PageView) {
        let duration = pageView.hasZoomed ? 0.1 : 0.5
        toggleControls(pageView: pageView, visible: !pageView.hasZoomed, duration: duration, delay: 0.5)
    }

    func pageView(_ pageView: PageView, didTouchPlayButton videoURL: URL) {
        LightboxConfig.handleVideo(self, videoURL)
    }

    func pageViewDidTouch(_ pageView: PageView) {
        guard !pageView.hasZoomed else { return }

        imageTouchDelegate?.lightboxController(self, didTouch: images[currentPage], at: currentPage)

        let visible = (headerView.alpha == 1.0)
        toggleControls(pageView: pageView, visible: !visible)
    }
}

// MARK: - HeaderViewDelegate

extension LightboxController: HeaderViewDelegate {

    func headerView(_ headerView: HeaderView, didPressDeleteButton deleteButton: UIButton) {
        deleteButton.isEnabled = false

        guard numberOfPages != 1 else {
            pageViews.removeAll()
            self.headerView(headerView, didPressCloseButton: headerView.closeButton)
            return
        }

        let prevIndex = currentPage

        if currentPage == numberOfPages - 1 {
            previous()
        } else {
            next()
            currentPage -= 1
        }

        pageViews.remove(at: prevIndex).removeFromSuperview()

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.5) { [weak self] in
            if self == nil {
                return
            }
            self?.configureLayout(self!.view.bounds.size)
            self?.currentPage = Int(self!.scrollView.contentOffset.x / self!.view.bounds.width)
            deleteButton.isEnabled = true
        }
    }

    func headerView(_ headerView: HeaderView, didPressCloseButton closeButton: UIButton) {
        closeButton.isEnabled = false
        presented = false
        dismissalDelegate?.lightboxControllerWillDismiss(self)
        dismiss(animated: true, completion: nil)
    }
}

// MARK: - FooterViewDelegate

extension LightboxController: FooterViewDelegate {

    public func footerView(_ footerView: FooterView, didExpand expanded: Bool) {
        UIView.animate(withDuration: 0.25, animations: { [weak self] in
            if self == nil {
                return
            }
            self!.overlayView.alpha = expanded ? 1.0 : 0.0
            self!.headerView.deleteButton.alpha = expanded ? 0.0 : 1.0
        })
    }
}