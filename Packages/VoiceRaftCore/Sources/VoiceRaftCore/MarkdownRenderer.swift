import Foundation

public struct MarkdownRenderer: MarkdownRendering, Sendable {
    public init() {}

    public func render(result: MeetingWorkflowResult) -> String {
        var lines = renderFrontmatter(result: result)

        if result.status == .needsReview {
            lines.append("> Review recommended: \(result.judgeSummary)")
            lines.append("")
        }

        lines.append(contentsOf: [
            "## Summary",
            result.sections.summary,
            "",
            "## Key Discussion Points",
        ])
        lines.append(contentsOf: renderBullets(result.sections.keyDiscussionPoints))
        lines.append(contentsOf: [
            "",
            "## Decisions",
        ])
        lines.append(contentsOf: renderBullets(result.sections.decisions))
        lines.append(contentsOf: [
            "",
            "## Action Items",
        ])
        lines.append(contentsOf: renderActionItems(result.sections.actionItems))
        lines.append(contentsOf: [
            "",
            "## Open Questions / Risks",
        ])
        lines.append(contentsOf: renderBullets(result.sections.openQuestionsOrRisks))
        lines.append(contentsOf: [
            "",
            "## Follow-Up",
        ])
        lines.append(contentsOf: renderBullets(result.sections.followUp))

        return lines.joined(separator: "\n")
    }

    private func renderFrontmatter(result: MeetingWorkflowResult) -> [String] {
        let tags = result.frontmatter.tags.joined(separator: ", ")
        return [
            "---",
            "title: \(result.frontmatter.title)",
            "date: \(result.frontmatter.date)",
            "meeting_mode: \(result.frontmatter.meetingMode)",
            "language: \(result.frontmatter.language)",
            "status: \(result.frontmatter.status.rawValue)",
            "tags: [\(tags)]",
            "---",
            "",
        ]
    }

    private func renderBullets(_ items: [String]) -> [String] {
        if items.isEmpty {
            return ["- None"]
        }
        return items.map { "- \($0)" }
    }

    private func renderActionItems(_ items: [ActionItem]) -> [String] {
        if items.isEmpty {
            return ["- None"]
        }

        return items.map { item in
            var detail = ["Owner: \(item.owner ?? "Unassigned")"]
            if let due = item.due {
                detail.append("Due: \(due)")
            }
            return "- \(item.task) (\(detail.joined(separator: ", ")))"
        }
    }
}
