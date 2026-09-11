import SwiftUI

struct ContentView: View {
    @State private var isMenuOpen = false
    @State private var selectedTab = "home"

    var body: some View {
        ZStack(alignment: .leading) {
            MainView(isMenuOpen: $isMenuOpen)

            if isMenuOpen {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut) { isMenuOpen = false }
                    }

                SideMenuView(selectedTab: $selectedTab, isMenuOpen: $isMenuOpen)
                    .frame(width: 260)
                    .transition(.move(edge: .leading))
                    .ignoresSafeArea()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isMenuOpen)
    }
}
