import SwiftUI

// MARK: - Sidebar Container

struct SidebarView: View {
    @ObservedObject var model: MarkdownDocumentModel
    @Binding var activePanel: SidebarPanel
    var onTOCClick: ((TOCHeading) -> Void)?
    var onCommentClick: ((ParsedComment) -> Void)?
    var onCommentEdit: ((ParsedComment) -> Void)?
    var onCommentDelete: ((ParsedComment) -> Void)?
    var onFileClick: ((String) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            SidebarChromeBackground(colorScheme: colorScheme)
            VStack(spacing: 0) {
                ActivityBar(
                    activePanel: $activePanel,
                    commentCount: model.parsedComments.count,
                    colorScheme: colorScheme
                )
                .background(QuickMDDesignTokens.surfaceContainerHigh(for: colorScheme))
                switch activePanel {
                case .toc:
                    TOCPanelView(
                        headings: model.tocHeadings,
                        activeHeadingID: model.activeTOCHeadingID,
                        onHeadingClick: { heading in onTOCClick?(heading) },
                        colorScheme: colorScheme
                    )
                case .comments:
                    CommentsPanelView(
                        comments: model.parsedComments,
                        onClick: { comment in onCommentClick?(comment) },
                        onEdit: { comment in onCommentEdit?(comment) },
                        onDelete: { comment in onCommentDelete?(comment) },
                        colorScheme: colorScheme
                    )
                case .files:
                    FilesPanelView(
                        nodes: model.fileTree,
                        currentFilePath: model.currentURL?.path ?? "",
                        onFileClick: { path in onFileClick?(path) },
                        colorScheme: colorScheme
                    )
                }
            }
        }
        .clipped()
    }
}

// MARK: - Activity Bar

struct ActivityBar: View {
    @Binding var activePanel: SidebarPanel
    var commentCount: Int
    var colorScheme: ColorScheme

    private var primary: Color { QuickMDDesignTokens.primary(for: colorScheme) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SidebarPanel.allCases, id: \.self) { panel in
                Button {
                    withAnimation(QuickMDDesignTokens.contentAnimation()) {
                        activePanel = panel
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: panel.icon)
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .foregroundStyle(activePanel == panel ? primary : QuickMDDesignTokens.onSurfaceVariant(for: colorScheme))

                        if panel == .comments && commentCount > 0 {
                            Text("\(commentCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 3)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(Color.orange)
                                .clipShape(Capsule())
                                .offset(x: -4, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .overlay(alignment: .leading) {
                    if activePanel == panel {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(primary)
                            .frame(width: 2)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
        .frame(height: 32)
    }
}

// MARK: - TOC Panel

struct TOCPanelView: View {
    let headings: [TOCHeading]
    let activeHeadingID: String?
    var onHeadingClick: ((TOCHeading) -> Void)?
    var colorScheme: ColorScheme

    var body: some View {
        if headings.isEmpty {
            VStack {
                Spacer()
                Text("No headings")
                    .foregroundStyle(QuickMDDesignTokens.onSurfaceVariant(for: colorScheme))
                    .font(.caption)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                List(headings) { heading in
                    Button {
                        onHeadingClick?(heading)
                    } label: {
                        HStack(spacing: 4) {
                            Text(heading.text)
                                .font(.system(size: fontSize(for: heading.level)))
                                .fontWeight(heading.level <= 2 ? .semibold : .regular)
                                .foregroundStyle(
                                    heading.id == activeHeadingID
                                        ? QuickMDDesignTokens.primary(for: colorScheme)
                                        : QuickMDDesignTokens.onSurface(for: colorScheme)
                                )
                                .lineLimit(2)
                                .truncationMode(.tail)
                            Spacer()
                        }
                        .padding(.leading, CGFloat((heading.level - 1) * 12))
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(
                        heading.id == activeHeadingID
                            ? QuickMDDesignTokens.surfaceContainerHighest(for: colorScheme)
                            : Color.clear
                    )
                    .id(heading.id)
                }
                .listStyle(.plain)
                .onChange(of: activeHeadingID) { _, newID in
                    if let newID {
                        withAnimation(QuickMDDesignTokens.contentAnimation()) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func fontSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return 13
        case 2: return 12.5
        default: return 12
        }
    }
}

// MARK: - Comments Panel

struct CommentsPanelView: View {
    let comments: [ParsedComment]
    var onClick: ((ParsedComment) -> Void)?
    var onEdit: ((ParsedComment) -> Void)?
    var onDelete: ((ParsedComment) -> Void)?
    var colorScheme: ColorScheme

    var body: some View {
        if comments.isEmpty {
            VStack {
                Spacer()
                Text("No comments")
                    .foregroundStyle(QuickMDDesignTokens.onSurfaceVariant(for: colorScheme))
                    .font(.caption)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(comments) { comment in
                CommentRow(
                    comment: comment,
                    onClick: { onClick?(comment) },
                    onEdit: { onEdit?(comment) },
                    onDelete: { onDelete?(comment) },
                    colorScheme: colorScheme
                )
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        }
    }
}

struct CommentRow: View {
    let comment: ParsedComment
    var onClick: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var colorScheme: ColorScheme
    @State private var isHovered = false

    var body: some View {
        Button {
            onClick?()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(comment.annotatedText.prefix(80))
                    .font(.system(size: 12))
                    .foregroundStyle(QuickMDDesignTokens.onSurface(for: colorScheme))
                    .lineLimit(2)
                Text(comment.comment)
                    .font(.system(size: 11))
                    .foregroundStyle(QuickMDDesignTokens.onSurfaceVariant(for: colorScheme))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .overlay(alignment: .topTrailing) {
                if isHovered {
                    HStack(spacing: 4) {
                        Button { onEdit?() } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        Button { onDelete?() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Files Panel

struct FilesPanelView: View {
    let nodes: [FileNode]
    let currentFilePath: String
    var onFileClick: ((String) -> Void)?
    var colorScheme: ColorScheme

    var body: some View {
        if nodes.isEmpty {
            VStack {
                Spacer()
                Text("No files")
                    .foregroundStyle(QuickMDDesignTokens.onSurfaceVariant(for: colorScheme))
                    .font(.caption)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                ForEach(nodes) { node in
                    FileNodeRow(
                        node: node,
                        currentFilePath: currentFilePath,
                        onFileClick: onFileClick,
                        colorScheme: colorScheme
                    )
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }
}

struct FileNodeRow: View {
    let node: FileNode
    let currentFilePath: String
    var onFileClick: ((String) -> Void)?
    var colorScheme: ColorScheme

    var body: some View {
        if node.isDirectory {
            DisclosureGroup {
                ForEach(node.children) { child in
                    FileNodeRow(
                        node: child,
                        currentFilePath: currentFilePath,
                        onFileClick: onFileClick,
                        colorScheme: colorScheme
                    )
                }
            } label: {
                Label(node.name, systemImage: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(QuickMDDesignTokens.onSurface(for: colorScheme))
            }
        } else {
            Button {
                onFileClick?(node.path)
            } label: {
                HStack {
                    Label(node.name, systemImage: "doc.text")
                        .font(.system(size: 12))
                        .foregroundStyle(
                            node.path == currentFilePath
                                ? QuickMDDesignTokens.primary(for: colorScheme)
                                : QuickMDDesignTokens.onSurface(for: colorScheme)
                        )
                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(
                node.path == currentFilePath
                    ? QuickMDDesignTokens.surfaceContainerHighest(for: colorScheme)
                    : Color.clear
            )
        }
    }
}

// MARK: - Resize Handle

struct SidebarResizeHandle: View {
    @Binding var width: Double
    var isLeading: Bool
    @GestureState private var dragStartWidth: Double? = nil

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($dragStartWidth) { _, state, _ in
                        if state == nil { state = width }
                    }
                    .onChanged { value in
                        let startWidth = dragStartWidth ?? width
                        let delta = isLeading ? value.translation.width : -value.translation.width
                        width = max(100, min(startWidth + delta, 500))
                    }
            )
    }
}
