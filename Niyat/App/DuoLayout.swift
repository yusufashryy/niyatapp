import SwiftUI

extension View {
    /// iPhone Duo: no vertical bar down the side of this screen (bars stay at
    /// the top and bottom), so content can use the whole width and sit
    /// centred on the fold. For screens that are a page or a book, not a list.
    ///
    /// `toolbarVerticalBehavior` is new in iOS 27.1 (SwiftUI 8.1). Older SDKs
    /// and iPhones without it keep the screen as it is.
    @ViewBuilder
    func horizontalBarsOnly() -> some View {
        #if canImport(SwiftUI, _version: 8.1)
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(.disabled)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
