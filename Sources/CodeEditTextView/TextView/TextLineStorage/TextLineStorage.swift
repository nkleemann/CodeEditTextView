//
//  TextLayoutLineStorage.swift
//
//
//  Created by Khan Winter on 6/25/23.
//

import Foundation

/// Implements a red-black tree for efficiently editing, storing and retrieving lines of text in a document.
final class TextLineStorage<Data: Identifiable> {
    internal var root: Node<Data>?

    /// The number of characters in the storage object.
    private(set) public var length: Int = 0
    /// The number of lines in the storage object
    private(set) public var count: Int = 0

    public var isEmpty: Bool { count == 0 }

    public var height: CGFloat = 0

    // TODO: Cache this value & update on tree update
    var first: TextLinePosition? {
        guard length > 0,
              let position = search(for: 0) else {
            return nil
        }
        return TextLinePosition(position: position)
    }

    // TODO: Cache this value & update on tree update
    var last: TextLinePosition? {
        guard length > 0 else { return nil }
        guard let position = search(for: length - 1) else {
            return nil
        }
        return TextLinePosition(position: position)
    }

    init() { }

    // MARK: - Public Methods

    /// Inserts a new line for the given range.
    /// - Parameters:
    ///   - line: The text line to insert
    ///   - range: The range the line represents. If the range is empty the line will be ignored.
    public func insert(line: Data, atIndex index: Int, length: Int, height: CGFloat) {
        assert(index >= 0 && index <= self.length, "Invalid index, expected between 0 and \(self.length). Got \(index)")
        defer {
            self.count += 1
            self.length += length
            self.height += height
        }

        let insertedNode = Node(
            length: length,
            data: line,
            leftSubtreeOffset: 0,
            leftSubtreeHeight: 0.0,
            leftSubtreeCount: 0,
            height: height,
            color: .black
        )
        guard root != nil else {
            root = insertedNode
            return
        }
        insertedNode.color = .red

        var currentNode = root
        var currentOffset: Int = root?.leftSubtreeOffset ?? 0
        while let node = currentNode {
            if currentOffset >= index {
                if node.left != nil {
                    currentNode = node.left
                    currentOffset = (currentOffset - node.leftSubtreeOffset) + (node.left?.leftSubtreeOffset ?? 0)
                } else {
                    node.left = insertedNode
                    insertedNode.parent = node
                    currentNode = nil
                }
            } else {
                if node.right != nil {
                    currentNode = node.right
                    currentOffset += node.length + (node.right?.leftSubtreeOffset ?? 0)
                } else {
                    node.right = insertedNode
                    insertedNode.parent = node
                    currentNode = nil
                }
            }
        }

        insertFixup(node: insertedNode)
    }

    /// Fetches a line for the given index.
    ///
    /// Complexity: `O(log n)`
    /// - Parameter index: The index to fetch for.
    /// - Returns: A text line object representing a generated line object and the offset in the document of the line.
    public func getLine(atIndex index: Int) -> TextLinePosition? {
        guard let nodePosition = search(for: index) else { return nil }
        return TextLinePosition(position: nodePosition)
    }

    /// Fetches a line for the given `y` value.
    ///
    /// Complexity: `O(log n)`
    /// - Parameter position: The position to fetch for.
    /// - Returns: A text line object representing a generated line object and the offset in the document of the line.
    public func getLine(atPosition posY: CGFloat) -> TextLinePosition? {
        var currentNode = root
        var currentOffset: Int = root?.leftSubtreeOffset ?? 0
        var currentYPosition: CGFloat = root?.leftSubtreeHeight ?? 0
        var currentIndex: Int = root?.leftSubtreeCount ?? 0
        while let node = currentNode {
            // If index is in the range [currentOffset..<currentOffset + length) it's in the line
            if posY >= currentYPosition && posY < currentYPosition + node.height {
                return TextLinePosition(
                    data: node.data,
                    range: NSRange(location: currentOffset, length: node.length),
                    yPos: currentYPosition,
                    height: node.height,
                    index: currentIndex
                )
            } else if currentYPosition > posY {
                currentNode = node.left
                currentOffset = (currentOffset - node.leftSubtreeOffset) + (node.left?.leftSubtreeOffset ?? 0)
                currentYPosition = (currentYPosition - node.leftSubtreeHeight) + (node.left?.leftSubtreeHeight ?? 0)
                currentIndex = (currentIndex - node.leftSubtreeCount) + (node.left?.leftSubtreeCount ?? 0)
            } else if node.leftSubtreeHeight < posY {
                currentNode = node.right
                currentOffset += node.length + (node.right?.leftSubtreeOffset ?? 0)
                currentYPosition += node.height + (node.right?.leftSubtreeHeight ?? 0)
                currentIndex += 1 + (node.right?.leftSubtreeCount ?? 0)
            } else {
                currentNode = nil
            }
        }

        return nil
    }

    /// Applies a length change at the given index.
    ///
    /// If a character was deleted, delta should be negative.
    /// The `index` parameter should represent where the edit began.
    ///
    /// Complexity: `O(m log n)` where `m` is the number of lines that need to be deleted as a result of this update.
    /// and `n` is the number of lines stored in the tree.
    ///
    /// Lines will be deleted if the delta is both negative and encompasses the entire line.
    ///
    /// If the delta goes beyond the line's range, an error will be thrown.
    /// - Parameters:
    ///   - index: The index where the edit began
    ///   - delta: The change in length of the document. Negative for deletes, positive for insertions.
    ///   - deltaHeight: The change in height of the document.
    public func update(atIndex index: Int, delta: Int, deltaHeight: CGFloat) {
        assert(index >= 0 && index < self.length, "Invalid index, expected between 0 and \(self.length). Got \(index)")
        assert(delta != 0 || deltaHeight != 0, "Delta must be non-0")
        guard let position = search(for: index) else {
            assertionFailure("No line found at index \(index)")
            return
        }
        if delta < 0 {
            assert(
                index - position.textPos > delta,
                "Delta too large. Deleting \(-delta) from line at position \(index) extends beyond the line's range."
            )
        }
        length += delta
        height += deltaHeight
        position.node.length += delta
        position.node.height += deltaHeight
        metaFixup(startingAt: position.node, delta: delta, deltaHeight: deltaHeight, insertedNode: false)
    }

    /// Deletes the line containing the given index.
    ///
    /// Will exit silently if a line could not be found for the given index, and throw an assertion error if the index
    /// is out of bounds.
    /// - Parameter index: The index to delete a line at.
    public func delete(lineAt index: Int) {
        assert(index >= 0 && index < self.length, "Invalid index, expected between 0 and \(self.length). Got \(index)")
        if count == 1 {
            removeAll()
            return
        }
        guard let node = search(for: index)?.node else { return }
        defer {
            count -= 1
        }

        var originalColor = node.color
        // Node to slice out
        var nodeY: Node<Data> = node
        // Node that replaces the sliced node.
        var nodeX: Node<Data>?

        if node.left == nil {
            nodeX = node.right
            transplant(node, with: node.right)
        } else if node.right == nil {
            nodeX = node.left
            transplant(node, with: node.left)
        } else {
            nodeY = node.right!.minimum() // node.right is not null by case 2
            originalColor = nodeY.color
            nodeX = nodeY.right
            if nodeY.parent == node {
                nodeX?.parent = nodeY
            } else {
                transplant(nodeY, with: nodeY.right)
                nodeY.right = node.right
                nodeY.right?.parent = nodeY
            }

            transplant(node, with: nodeY)
            nodeY.left = node.left
            nodeY.left?.parent = nodeY
            nodeY.color = node.color
        }

//        if (z.left == TNULL) {
//            x = z.right;
//            rbTransplant(z, z.right);
//        } else if (z.right == TNULL) {
//            x = z.left;
//            rbTransplant(z, z.left);
//        } else {
//            y = minimum(z.right);
//            yOriginalColor = y.color;
//            x = y.right;
//            if (y.parent == z) {
//                x.parent = y;
//            } else {
//                rbTransplant(y, y.right);
//                y.right = z.right;
//                y.right.parent = y;
//            }
//
//            rbTransplant(z, y);
//            y.left = z.left;
//            y.left.parent = y;
//            y.color = z.color;
//        }
//        if (yOriginalColor == 0) {
//            fixDelete(x);
//        }
    }

    public func removeAll() {
        root = nil
        count = 0
        length = 0
        height = 0
    }

    public func printTree() {
        print(
            treeString(root!) { node in
                (
                    // swiftlint:disable:next line_length
                    "\(node.length)[\(node.leftSubtreeOffset)\(node.color == .red ? "R" : "B")][\(node.height), \(node.leftSubtreeHeight)]",
                    node.left,
                    node.right
                )
            }
        )
        print("")
    }

    /// Efficiently builds the tree from the given array of lines.
    /// - Parameter lines: The lines to use to build the tree.
    public func build(from lines: [BuildItem], estimatedLineHeight: CGFloat) {
        root = build(lines: lines, estimatedLineHeight: estimatedLineHeight, left: 0, right: lines.count, parent: nil).0
        count = lines.count
    }

    /// Recursively builds a subtree given an array of sorted lines, and a left and right indexes.
    /// - Parameters:
    ///   - lines: The lines to use to build the subtree.
    ///   - estimatedLineHeight: An estimated line height to add to the allocated nodes.
    ///   - left: The left index to use.
    ///   - right: The right index to use.
    ///   - parent: The parent of the subtree, `nil` if this is the root.
    /// - Returns: A node, if available, along with it's subtree's height and offset.
    private func build(
        lines: [BuildItem],
        estimatedLineHeight: CGFloat,
        left: Int,
        right: Int,
        parent: Node<Data>?
    ) -> (Node<Data>?, Int?, CGFloat?, Int) { // swiftlint:disable:this large_tuple
        guard left < right else { return (nil, nil, nil, 0) }
        let mid = left + (right - left)/2
        let node = Node(
            length: lines[mid].length,
            data: lines[mid].data,
            leftSubtreeOffset: 0,
            leftSubtreeHeight: 0,
            leftSubtreeCount: 0,
            height: estimatedLineHeight,
            color: .black
        )
        node.parent = parent

        let (left, leftOffset, leftHeight, leftCount) = build(
            lines: lines,
            estimatedLineHeight: estimatedLineHeight,
            left: left,
            right: mid,
            parent: node
        )
        let (right, rightOffset, rightHeight, rightCount) = build(
            lines: lines,
            estimatedLineHeight: estimatedLineHeight,
            left: mid + 1,
            right: right,
            parent: node
        )
        node.left = left
        node.right = right

        if node.left == nil && node.right == nil {
            node.color = .red
        }

        length += node.length
        height += node.height
        node.leftSubtreeOffset = leftOffset ?? 0
        node.leftSubtreeHeight = leftHeight ?? 0
        node.leftSubtreeCount = leftCount

        return (
            node,
            node.length + (leftOffset ?? 0) + (rightOffset ?? 0),
            node.height + (leftHeight ?? 0) + (rightHeight ?? 0),
            1 + leftCount + rightCount
        )
    }
}

private extension TextLineStorage {
    // MARK: - Search

    /// Searches for the given index. Returns a node and offset if found.
    /// - Parameter index: The index to look for in the document.
    /// - Returns: A tuple containing a node if it was found, and the offset of the node in the document.
    func search(for index: Int) -> NodePosition? {
        var currentNode = root
        var currentOffset: Int = root?.leftSubtreeOffset ?? 0
        var currentYPosition: CGFloat = root?.leftSubtreeHeight ?? 0
        var currentIndex: Int = root?.leftSubtreeCount ?? 0
        while let node = currentNode {
            // If index is in the range [currentOffset..<currentOffset + length) it's in the line
            if index >= currentOffset && index < currentOffset + node.length {
                return NodePosition(node: node, yPos: currentYPosition, textPos: currentOffset, index: currentIndex)
            } else if currentOffset > index {
                currentNode = node.left
                currentOffset = (currentOffset - node.leftSubtreeOffset) + (node.left?.leftSubtreeOffset ?? 0)
                currentYPosition = (currentYPosition - node.leftSubtreeHeight) + (node.left?.leftSubtreeHeight ?? 0)
                currentIndex = (currentIndex - node.leftSubtreeCount) + (node.left?.leftSubtreeCount ?? 0)
            } else if node.leftSubtreeOffset < index {
                currentNode = node.right
                currentOffset += node.length + (node.right?.leftSubtreeOffset ?? 0)
                currentYPosition += node.height + (node.right?.leftSubtreeHeight ?? 0)
                currentIndex += 1 + (node.right?.leftSubtreeCount ?? 0)
            } else {
                currentNode = nil
            }
        }

        return nil
    }

    // MARK: - Fixup

    func insertFixup(node: Node<Data>) {
        metaFixup(startingAt: node, delta: node.length, deltaHeight: node.height, insertedNode: true)

        var nextNode: Node<Data>? = node
        while var nodeX = nextNode, nodeX != root, let nodeXParent = nodeX.parent, nodeXParent.color == .red {
            let nodeY = sibling(nodeXParent)
            if isLeftChild(nodeXParent) {
                if nodeY?.color == .red {
                    nodeXParent.color = .black
                    nodeY?.color = .black
                    nodeX.parent?.parent?.color = .red
                    nextNode = nodeX.parent?.parent
                } else {
                    if isRightChild(nodeX) {
                        nodeX = nodeXParent
                        leftRotate(node: nodeX)
                    }

                    nodeX.parent?.color = .black
                    nodeX.parent?.parent?.color = .red
                    if let grandparent = nodeX.parent?.parent {
                        rightRotate(node: grandparent)
                    }
                }
            } else {
                if nodeY?.color == .red {
                    nodeXParent.color = .black
                    nodeY?.color = .black
                    nodeX.parent?.parent?.color = .red
                    nextNode = nodeX.parent?.parent
                } else {
                    if isLeftChild(nodeX) {
                        nodeX = nodeXParent
                        rightRotate(node: nodeX)
                    }

                    nodeX.parent?.color = .black
                    nodeX.parent?.parent?.color = .red
                    if let grandparent = nodeX.parent?.parent {
                        leftRotate(node: grandparent)
                    }
                }
            }
        }

        root?.color = .black
    }

    /// RB Tree Deletes `:(`
    func deleteFixup(node: Node<Data>) {

    }

    /// Walk up the tree, updating any `leftSubtree` metadata.
    func metaFixup(startingAt node: Node<Data>, delta: Int, deltaHeight: CGFloat, insertedNode: Bool) {
        guard node.parent != nil else { return }
        var node: Node? = node
        while node != nil, node != root {
            if isLeftChild(node!) {
                node?.parent?.leftSubtreeOffset += delta
                node?.parent?.leftSubtreeHeight += deltaHeight
                node?.parent?.leftSubtreeCount += insertedNode ? 1 : 0
            }
            node = node?.parent
        }
    }

    func calculateSize(_ node: Node<Data>?) -> Int {
        guard let node else { return 0 }
        return node.length + node.leftSubtreeOffset + calculateSize(node.right)
    }
}

// MARK: - Rotations

private extension TextLineStorage {
    func rightRotate(node: Node<Data>) {
        rotate(node: node, left: false)
    }

    func leftRotate(node: Node<Data>) {
        rotate(node: node, left: true)
    }

    func rotate(node: Node<Data>, left: Bool) {
        var nodeY: Node<Data>?

        if left {
            nodeY = node.right
            nodeY?.leftSubtreeOffset += node.leftSubtreeOffset + node.length
            nodeY?.leftSubtreeHeight += node.leftSubtreeHeight + node.height
            nodeY?.leftSubtreeCount += node.leftSubtreeCount + 1
            node.right = nodeY?.left
            node.right?.parent = node
        } else {
            nodeY = node.left
            node.left = nodeY?.right
            node.left?.parent = node
        }

        nodeY?.parent = node.parent
        if node.parent == nil {
            if let node = nodeY {
                root = node
            }
        } else if isLeftChild(node) {
            node.parent?.left = nodeY
        } else if isRightChild(node) {
            node.parent?.right = nodeY
        }

        if left {
            nodeY?.left = node
        } else {
            nodeY?.right = node
            node.leftSubtreeOffset = (node.left?.length ?? 0) + (node.left?.leftSubtreeOffset ?? 0)
            node.leftSubtreeHeight = (node.left?.height ?? 0) + (node.left?.leftSubtreeHeight ?? 0)
            node.leftSubtreeCount = (node.left == nil ? 1 : 0) + (node.left?.leftSubtreeCount ?? 0)
        }
        node.parent = nodeY
    }
}

// swiftlint:disable all
// Awesome tree printing function from https://stackoverflow.com/a/43903427/10453550
public func treeString<T>(_ node:T, reversed:Bool=false, isTop:Bool=true, using nodeInfo:(T)->(String,T?,T?)) -> String {
    // node value string and sub nodes
    let (stringValue, leftNode, rightNode) = nodeInfo(node)

    let stringValueWidth  = stringValue.count

    // recurse to sub nodes to obtain line blocks on left and right
    let leftTextBlock     = leftNode  == nil ? []
    : treeString(leftNode!,reversed:reversed,isTop:false,using:nodeInfo)
        .components(separatedBy:"\n")

    let rightTextBlock    = rightNode == nil ? []
    : treeString(rightNode!,reversed:reversed,isTop:false,using:nodeInfo)
        .components(separatedBy:"\n")

    // count common and maximum number of sub node lines
    let commonLines       = min(leftTextBlock.count,rightTextBlock.count)
    let subLevelLines     = max(rightTextBlock.count,leftTextBlock.count)

    // extend lines on shallower side to get same number of lines on both sides
    let leftSubLines      = leftTextBlock
    + Array(repeating:"", count: subLevelLines-leftTextBlock.count)
    let rightSubLines     = rightTextBlock
    + Array(repeating:"", count: subLevelLines-rightTextBlock.count)

    // compute location of value or link bar for all left and right sub nodes
    //   * left node's value ends at line's width
    //   * right node's value starts after initial spaces
    let leftLineWidths    = leftSubLines.map{$0.count}
    let rightLineIndents  = rightSubLines.map{$0.prefix{$0==" "}.count  }

    // top line value locations, will be used to determine position of current node & link bars
    let firstLeftWidth    = leftLineWidths.first   ?? 0
    let firstRightIndent  = rightLineIndents.first ?? 0


    // width of sub node link under node value (i.e. with slashes if any)
    // aims to center link bars under the value if value is wide enough
    //
    // ValueLine:    v     vv    vvvvvv   vvvvv
    // LinkLine:    / \   /  \    /  \     / \
    //
    let linkSpacing       = min(stringValueWidth, 2 - stringValueWidth % 2)
    let leftLinkBar       = leftNode  == nil ? 0 : 1
    let rightLinkBar      = rightNode == nil ? 0 : 1
    let minLinkWidth      = leftLinkBar + linkSpacing + rightLinkBar
    let valueOffset       = (stringValueWidth - linkSpacing) / 2

    // find optimal position for right side top node
    //   * must allow room for link bars above and between left and right top nodes
    //   * must not overlap lower level nodes on any given line (allow gap of minSpacing)
    //   * can be offset to the left if lower subNodes of right node
    //     have no overlap with subNodes of left node
    let minSpacing        = 2
    let rightNodePosition = zip(leftLineWidths,rightLineIndents[0..<commonLines])
        .reduce(firstLeftWidth + minLinkWidth)
    { max($0, $1.0 + minSpacing + firstRightIndent - $1.1) }


    // extend basic link bars (slashes) with underlines to reach left and right
    // top nodes.
    //
    //        vvvvv
    //       __/ \__
    //      L       R
    //
    let linkExtraWidth    = max(0, rightNodePosition - firstLeftWidth - minLinkWidth )
    let rightLinkExtra    = linkExtraWidth / 2
    let leftLinkExtra     = linkExtraWidth - rightLinkExtra

    // build value line taking into account left indent and link bar extension (on left side)
    let valueIndent       = max(0, firstLeftWidth + leftLinkExtra + leftLinkBar - valueOffset)
    let valueLine         = String(repeating:" ", count:max(0,valueIndent))
    + stringValue
    let slash             = reversed ? "\\" : "/"
    let backSlash         = reversed ? "/"  : "\\"
    let uLine             = reversed ? "¯"  : "_"
    // build left side of link line
    let leftLink          = leftNode == nil ? ""
    : String(repeating: " ", count:firstLeftWidth)
    + String(repeating: uLine, count:leftLinkExtra)
    + slash

    // build right side of link line (includes blank spaces under top node value)
    let rightLinkOffset   = linkSpacing + valueOffset * (1 - leftLinkBar)
    let rightLink         = rightNode == nil ? ""
    : String(repeating:  " ", count:rightLinkOffset)
    + backSlash
    + String(repeating:  uLine, count:rightLinkExtra)

    // full link line (will be empty if there are no sub nodes)
    let linkLine          = leftLink + rightLink

    // will need to offset left side lines if right side sub nodes extend beyond left margin
    // can happen if left subtree is shorter (in height) than right side subtree
    let leftIndentWidth   = max(0,firstRightIndent - rightNodePosition)
    let leftIndent        = String(repeating:" ", count:leftIndentWidth)
    let indentedLeftLines = leftSubLines.map{ $0.isEmpty ? $0 : (leftIndent + $0) }

    // compute distance between left and right sublines based on their value position
    // can be negative if leading spaces need to be removed from right side
    let mergeOffsets      = indentedLeftLines
        .map{$0.count}
        .map{leftIndentWidth + rightNodePosition - firstRightIndent - $0 }
        .enumerated()
        .map{ rightSubLines[$0].isEmpty ? 0  : $1 }


    // combine left and right lines using computed offsets
    //   * indented left sub lines
    //   * spaces between left and right lines
    //   * right sub line with extra leading blanks removed.
    let mergedSubLines    = zip(mergeOffsets.enumerated(),indentedLeftLines)
        .map{ ( $0.0, $0.1, $1 + String(repeating:" ", count:max(0,$0.1)) ) }
        .map{ $2 + String(rightSubLines[$0].dropFirst(max(0,-$1))) }

    // Assemble final result combining
    //  * node value string
    //  * link line (if any)
    //  * merged lines from left and right sub trees (if any)
    let treeLines = [leftIndent + valueLine]
    + (linkLine.isEmpty ? [] : [leftIndent + linkLine])
    + mergedSubLines

    return (reversed && isTop ? treeLines.reversed(): treeLines)
        .joined(separator:"\n")
}
// swiftlint:enable all
