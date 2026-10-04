import Foundation
var failures = 0
func check(_ c: Bool, _ m: String) { if c { print("ok  :", m) } else { print("FAIL:", m); failures += 1 } }

check(ChatLogic.title(from: "  Hello there\nsecond line") == "Hello there", "title uses the first line")
check(ChatLogic.title(from: "") == "New chat" && ChatLogic.title(from: "   \n ") == "New chat", "empty title falls back")
let long = String(repeating: "word ", count: 30)
check(ChatLogic.title(from: long).count <= 41 && ChatLogic.title(from: long).hasSuffix("…"), "long title is truncated with an ellipsis")

let msgs = (1...12).map { ChatMessage(role: $0 % 2 == 1 ? .user : .assistant, text: "message number \($0) " + String(repeating: "x", count: 100)) }
let r = ChatLogic.recap(of: msgs, maxChars: 400)
check(r.contains("message number 12") && !r.contains("message number 1 "), "recap keeps the newest messages first")
check(r.count <= 520, "recap respects the size budget (\(r.count) chars)")
check(r.split(separator: "\n").first!.contains("message number") && r.range(of: "message number 11")!.lowerBound < r.range(of: "message number 12")!.lowerBound, "recap stays in chronological order")
check(ChatLogic.recap(of: [], maxChars: 100) == "", "empty history gives an empty recap")
var errMsg = ChatMessage(role: .assistant, text: "boom"); errMsg.isError = true
check(ChatLogic.recap(of: [errMsg], maxChars: 100) == "", "error messages are not replayed to the model")
let cut = ChatLogic.recap(of: [ChatMessage(role: .user, text: String(repeating: "a", count: 2000))], maxChars: 5000, perMessage: 500)
check(cut.count < 520, "a single huge message is trimmed")

var s = ChatSettings()
check(s.instructions.contains("not sure"), "instructions always ask the model to admit uncertainty")
s.persona = .custom; s.custom = "  Talk like a pirate.  "
check(s.instructions.hasPrefix("Talk like a pirate."), "custom persona uses the custom text")
s.custom = "   "
check(s.instructions.hasPrefix(Persona.assistant.instructions), "blank custom text falls back to the assistant persona")
s.creativity = 0; check(s.temperature == 0, "creativity 0 -> temperature 0")
s.creativity = 1; check(abs(s.temperature - 1.5) < 1e-9, "creativity 1 -> temperature 1.5")
s.creativity = 5; check(abs(s.temperature - 1.5) < 1e-9, "creativity is clamped")
check(ResponseLength.short.maxTokens < ResponseLength.normal.maxTokens && ResponseLength.normal.maxTokens < ResponseLength.long.maxTokens, "response length caps increase")
var a = ChatSettings(), b = ChatSettings(); b.persona = .tutor
check(a.signature != b.signature, "changing the persona changes the session signature")
let full = ChatLogic.sessionInstructions(settings: a, history: Array(msgs.prefix(2)), recapChars: 1000)
check(full.contains("The conversation so far:") && full.contains(a.instructions), "session instructions include recap")
check(ChatLogic.sessionInstructions(settings: a, history: [], recapChars: 1000) == a.instructions, "no history -> plain instructions")
let conv = Conversation(title: "t", messages: [ChatMessage(role: .user, text: "hi")])
let data = try! JSONEncoder().encode([conv]); let back = try! JSONDecoder().decode([Conversation].self, from: data)
check(back == [conv], "conversations survive a JSON round trip")
print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
