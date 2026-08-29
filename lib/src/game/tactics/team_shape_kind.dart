/// The five shapes every formation owns (plan items 4 and 24). The visible
/// formation never changes officially — the behavioural structure morphs
/// automatically: a 4-3-3 defends as a 4-5-1 and can attack like a 2-3-5.
enum TeamShapeKind {
  base,
  attacking,
  defensive,
  pressing,
  transition,
}
