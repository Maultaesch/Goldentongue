class Rank {
  final String name;
  final int minXp;
  const Rank(this.name, this.minXp);
}

const ranks = <Rank>[
  Rank('Beginner', 0),
  Rank('Social Explorer', 100),
  Rank('Communicator', 300),
  Rank('Social Leader', 600),
  Rank('Charismatic Speaker', 1000),
  Rank('Master Communicator', 1600),
  Rank('Elite Communicator', 2500),
];

int rankIndexFor(int xp) {
  var index = 0;
  for (var i = 0; i < ranks.length; i++) {
    if (xp >= ranks[i].minXp) index = i;
  }
  return index;
}

/// Progress (0..1) toward the next rank.
double rankProgress(int xp) {
  final i = rankIndexFor(xp);
  if (i == ranks.length - 1) return 1;
  final from = ranks[i].minXp;
  final to = ranks[i + 1].minXp;
  return ((xp - from) / (to - from)).clamp(0.0, 1.0);
}
