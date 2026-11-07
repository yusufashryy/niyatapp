import SwiftUI
import UIKit

/// Mushaf pages turned like paper (UIKit's page curl), right to left: one
/// page bound on its right edge, or two facing pages with the spine in the
/// middle. Changing `spread` needs a new pager (give it `.id(spread)`),
/// because UIKit fixes the spine when the controller is made.
struct MushafCurlPager<Page: View>: UIViewControllerRepresentable {
    @Binding var page: Int
    let spread: Bool
    /// Off while a page is zoomed, so dragging moves around the page instead.
    let isEnabled: Bool
    let paper: UIColor
    let content: (Int) -> Page

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        // UIKit orders pages left to right. A mushaf runs the other way, so
        // here the page to the left is the next one (see the data source).
        let spine: UIPageViewController.SpineLocation = spread ? .mid : .max
        let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
                                              options: [.spineLocation: NSNumber(value: spine.rawValue)])
        controller.isDoubleSided = spread
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .clear
        // Tapping near an edge would turn the page instead of selecting the
        // verse under your finger: turn by dragging only.
        for recognizer in controller.gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }
        controller.setViewControllers(context.coordinator.hosts(showing: page), direction: .forward, animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        for recognizer in controller.gestureRecognizers where recognizer is UIPanGestureRecognizer {
            recognizer.isEnabled = isEnabled
        }
        let visible = controller.viewControllers?.compactMap { $0 as? PageHost } ?? []
        if visible.contains(where: { $0.number == page }) {
            // Same pages: refresh what's drawn on them (ribbon, colours, the current page).
            for host in visible { coordinator.refresh(host) }
        } else if !coordinator.isTurning {
            // Moved elsewhere (a jump or following a recitation): turn there,
            // curling only to a neighbouring page.
            let shown = visible.map(\.number).min() ?? page
            let near = abs(page - shown) <= (spread ? 2 : 1)
            // In UIKit's left-to-right order, a later mushaf page comes "before".
            controller.setViewControllers(coordinator.hosts(showing: page), direction: page > shown ? .reverse : .forward,
                                          animated: near)
        }
    }

    final class PageHost: UIHostingController<AnyView> {
        let number: Int

        init(number: Int, root: AnyView, paper: UIColor) {
            self.number = number
            super.init(rootView: root)
            safeAreaRegions = []
            view.backgroundColor = paper
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: MushafCurlPager
        /// A page turn is under way; don't reset the pages under it.
        private(set) var isTurning = false

        init(_ parent: MushafCurlPager) { self.parent = parent }

        func host(_ number: Int) -> PageHost {
            PageHost(number: number, root: AnyView(parent.content(number)), paper: parent.paper)
        }

        func refresh(_ host: PageHost) {
            host.rootView = AnyView(parent.content(host.number))
            host.view.backgroundColor = parent.paper
        }

        /// The pages to show for `page`: itself, or its spread as [left, right].
        func hosts(showing page: Int) -> [UIViewController] {
            guard parent.spread else { return [host(page)] }
            let spread = MushafBook.spread(containing: page)
            return [host(spread.left ?? spread.right), host(spread.right)]
        }

        // Left of a page (UIKit's "before") comes the next mushaf page.
        func pageViewController(_ controller: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            (viewController as? PageHost).flatMap { MushafBook.page(after: $0.number) }.map(host)
        }

        func pageViewController(_ controller: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            (viewController as? PageHost).flatMap { MushafBook.page(before: $0.number) }.map(host)
        }

        func pageViewController(_ controller: UIPageViewController,
                                willTransitionTo pendingViewControllers: [UIViewController]) {
            isTurning = true
        }

        func pageViewController(_ controller: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            isTurning = false
            guard completed, let shown = controller.viewControllers?.compactMap({ ($0 as? PageHost)?.number }).min(),
                  shown != parent.page else { return }
            parent.page = shown
        }
    }
}
