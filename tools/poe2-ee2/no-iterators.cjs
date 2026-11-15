// A Babel plugin for ee2kit.js: a for-of over an array becomes an index
// loop, so Qt's JavaScript makes no array iterator for it. MN's 0.8.43
// crashed in Qt's interpreter in Runtime::GetIterator ->
// ExecutionEngine::newArrayIteratorObject (QA, 2026-11-15), reached from
// the kit. Other iterables (Map, Set, strings, generators) keep the plain
// for-of in a second branch, so nothing changes in what the loop does.
//
//   for (const x of list) body
// becomes
//   { const _a = list;
//     if (Array.isArray(_a)) for (let _i = 0; _i < _a.length; _i++) { const x = _a[_i]; body }
//     else for (const x of _a) body }
module.exports = function noIterators({ types: t }) {
  return {
    name: "gc-no-array-iterators",
    visitor: {
      ForOfStatement(path) {
        const node = path.node;
        if (node.await || node._gcDone) return;
        const labelled = path.parentPath.isLabeledStatement() ? path.parentPath : null;
        const scope = path.scope;
        const list = scope.generateUidIdentifier("a");
        const i = scope.generateUidIdentifier("i");
        const item = t.memberExpression(t.cloneNode(list), t.cloneNode(i), true);
        let first;
        if (t.isVariableDeclaration(node.left)) {
          const d = node.left.declarations[0];
          first = t.variableDeclaration(node.left.kind, [t.variableDeclarator(t.cloneNode(d.id, true), item)]);
        } else {
          first = t.expressionStatement(t.assignmentExpression("=", t.cloneNode(node.left, true), item));
        }
        const body = t.isBlockStatement(node.body) ? node.body.body : [node.body];
        const indexLoop = t.forStatement(
          t.variableDeclaration("let", [t.variableDeclarator(i, t.numericLiteral(0))]),
          t.binaryExpression("<", t.cloneNode(i), t.memberExpression(t.cloneNode(list), t.identifier("length"))),
          t.updateExpression("++", t.cloneNode(i)),
          t.blockStatement([first, ...body.map((s) => t.cloneNode(s, true))]),
        );
        const plain = t.forOfStatement(t.cloneNode(node.left, true), t.cloneNode(list), node.body);
        plain._gcDone = true;
        const wrap = (loop) => (labelled ? t.labeledStatement(t.identifier(labelled.node.label.name), loop) : loop);
        const block = t.blockStatement([
          t.variableDeclaration("const", [t.variableDeclarator(list, node.right)]),
          t.ifStatement(
            t.callExpression(t.memberExpression(t.identifier("Array"), t.identifier("isArray")), [t.cloneNode(list)]),
            wrap(indexLoop),
            wrap(plain),
          ),
        ]);
        (labelled || path).replaceWith(block);
      },
    },
  };
};
