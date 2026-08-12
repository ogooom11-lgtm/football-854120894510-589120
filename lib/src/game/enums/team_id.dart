enum TeamId { blue, red }

enum TeamSide { left, right }

extension TeamIdText on TeamId {
  String get turkishName => switch (this) {
        TeamId.blue => 'Mavi',
        TeamId.red => 'Kirmizi',
      };

  TeamId get opponent => this == TeamId.blue ? TeamId.red : TeamId.blue;
}

extension TeamSideText on TeamSide {
  TeamSide get opposite => this == TeamSide.left ? TeamSide.right : TeamSide.left;
}
