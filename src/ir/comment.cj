package cjbind.ir

import std.collection.{collectArray, collectArrayList}

public enum CommentKind {
    SingleLines
    | MultiLine
}

/// 转义注释文本中会破坏 Cangjie 注释定界符的字符序列：
/// - `*/` → `*\/`、`/*` → `/\*`：防止提前终止或意外嵌套块注释
/// - 换行符 → 字面 `\n`：防止逃逸行注释（Cangjie 行注释仅被 `\n` 终止）
public func escapeComment(s: String): String {
    s.replace("*/", "*\\/")
        .replace("/*", "/\\*")
        .replace("\r\n", "\\n")
        .replace("\n", "\\n")
        .replace("\r", "\\n")
}

func commentKind(comment: String): ?CommentKind {
    if (comment.startsWith("/*")) {
        return Some(CommentKind.MultiLine)
    } else if (comment.startsWith("//")) {
        return Some(CommentKind.SingleLines)
    } else {
        return None
    }
}

public func preprocessComment(comment: String): String {
    match (commentKind(comment)) {
        case Some(CommentKind.SingleLines) => return preprocessSingleLines(comment)
        case Some(CommentKind.MultiLine) => return preprocessMultiLines(comment)
        case None => return comment
    }
}

public func preprocessSingleLines(comment: String): String {
    let lines = comment.lines().map {
        l => l.trimAscii().trimStart([r'/'])
    } |> collectArray
    return String.join(lines, delimiter: "\n")
}

public func preprocessMultiLines(comment: String): String {
    let comment2 = comment.trimStart([r'/']).trimEnd([r'*', r'/'])

    let lines = comment2.lines().map {l => l.trimAscii().trimStart([r'*', r'!'])} |> collectArrayList

    var foundContent = false
    let ret = StringBuilder()

    for((idx, v) in lines.iterator().enumerate()) {
        let hasContent = !v.trimAscii().isEmpty()
        if (hasContent) {
            foundContent = true
        } else if (!foundContent) {
            continue
        }

        if (idx == lines.size - 1) {
            if (!hasContent) {
                continue
            }
        }

        ret.append(v)
        ret.append("\n")
    }

    return ret.toString()
}
