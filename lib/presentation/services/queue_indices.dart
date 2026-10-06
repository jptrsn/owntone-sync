// The two play-order <-> base index translations any queue UI needs
// (index-space invariant: `currentIndex` indexes `sequence` in base order;
// `shuffleIndices` is the list of base indices in play order).
//
// Extracted from the queue sheet's private methods so the translation can
// be tested directly; the previous session that inverted this model
// (treating `currentIndex` as a play position) is what these guard against.

/// The play-order row (the queue sheet's highlight row) that [baseIndex]
/// currently occupies, or null when nothing is current.
int? queueCurrentRow(List<int> shuffleIndices, int? baseIndex, bool shuffleOn) {
  if (baseIndex == null) return null;
  if (!shuffleOn) return baseIndex;
  return shuffleIndices.indexOf(baseIndex);
}

/// The base index to play when the user picks play-order row [row]
/// (the argument for `skipToQueueItem` / `seek(index:)`).
int queueBaseIndexForRow(int row, List<int> shuffleIndices, bool shuffleOn) {
  return shuffleOn ? shuffleIndices[row] : row;
}
