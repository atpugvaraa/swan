/// Everything public here becomes Java API.
public struct Track {
    public var title: String
    public var seconds: Int64

    public init(title: String, seconds: Int64) {
        self.title = title
        self.seconds = seconds
    }

    public func describe() -> String {
        "\(title) (\(seconds / 60):\(seconds % 60 < 10 ? "0" : "")\(seconds % 60))"
    }
}

public func longest(_ first: Track, _ second: Track) -> Track {
    first.seconds >= second.seconds ? first : second
}

public func fibonacci(_ n: Int64) -> Int64 {
    n < 2 ? n : fibonacci(n - 1) + fibonacci(n - 2)
}
