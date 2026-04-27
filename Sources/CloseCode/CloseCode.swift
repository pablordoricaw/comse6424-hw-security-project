// The Swift Programming Language
// https://docs.swift.org/swift-book
import TUIkit

@main
struct CloseCode: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var count = 0
    @State private var selected: String?

    var body: some View {
        VStack {
            Spacer()

            Text("Welcome to TUIkit")
                .bold()
                .foregroundStyle(.palette.accent)
                .padding(.bottom)

            HStack {
                Button("Increment") { count += 1 }
                Text("Count: \(count)")
            }

            Spacer()

            List("Items", selection: $selected) {
                ForEach(["Alpha", "Beta", "Gamma", "Delta"], id: \.self) { item in
                    Text(item)
                }
            }
            .frame(width: 21)

            Spacer()
            Spacer()
        }
        .padding()
        .appHeader {
            HStack {
                Text("My TUIkit App").bold()
                Spacer()
                Text("v1.0")
            }
        }
        .statusBarSystemItems(
            theme: true,
            appearance: true
        )
    }
}
