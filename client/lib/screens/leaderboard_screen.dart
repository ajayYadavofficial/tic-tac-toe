import 'package:flutter/material.dart';

import '../models/game_state.dart';

// Reuse lobby theme colors
const _kBlue = Color(0xFF4A90D9);
const _kCoral = Color(0xFFE8734A);
const _kBg = Color(0xFFF8F9FC);
const _kCardBg = Colors.white;
const _kTextPrimary = Color(0xFF2D3142);
const _kTextSecondary = Color(0xFF9A9BB2);

class LeaderboardScreen extends StatelessWidget {
  final List<LeaderboardEntry> entries;

  const LeaderboardScreen({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 24, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: _kTextPrimary,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Leaderboard',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _kTextPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      size: 22,
                      color: Color(0xFFD97706),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Podium for top 3 ──
            if (entries.length >= 3)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildPodium(),
              ),

            const SizedBox(height: 16),

            // ── Rest of the list ──
            Expanded(
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  // Skip top 3 if podium is shown
                  if (entries.length >= 3 && i < 3) {
                    return const SizedBox.shrink();
                  }
                  return _FullLeaderboardRow(entry: entries[i]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPodium() {
    final first = entries[0];
    final second = entries[1];
    final third = entries[2];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 2nd place
        Expanded(child: _PodiumCard(entry: second, height: 100, place: 2)),
        const SizedBox(width: 10),
        // 1st place
        Expanded(child: _PodiumCard(entry: first, height: 130, place: 1)),
        const SizedBox(width: 10),
        // 3rd place
        Expanded(child: _PodiumCard(entry: third, height: 80, place: 3)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Podium Card (top 3)
// ═══════════════════════════════════════════════════════════════

class _PodiumCard extends StatelessWidget {
  final LeaderboardEntry entry;
  final double height;
  final int place;

  const _PodiumCard({
    required this.entry,
    required this.height,
    required this.place,
  });

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (place) {
      1 => (const Color(0xFFD97706), Icons.looks_one_rounded),
      2 => (const Color(0xFF6B7280), Icons.looks_two_rounded),
      _ => (const Color(0xFF92400E), Icons.looks_3_rounded),
    };

    final bgColor = switch (place) {
      1 => const Color(0xFFFEF3C7),
      2 => const Color(0xFFF3F4F6),
      _ => const Color(0xFFFED7AA),
    };

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: place == 1 ? 32 : 26),
          const SizedBox(height: 6),
          Text(
            entry.username.isNotEmpty ? entry.username : 'Anon',
            style: TextStyle(
              fontSize: place == 1 ? 14 : 12,
              fontWeight: FontWeight.w700,
              color: _kTextPrimary,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${entry.score}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Full Leaderboard Row (rank 4+)
// ═══════════════════════════════════════════════════════════════

class _FullLeaderboardRow extends StatelessWidget {
  final LeaderboardEntry entry;

  const _FullLeaderboardRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Rank number
          SizedBox(
            width: 32,
            child: Text(
              '#${entry.rank}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _kTextSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Avatar circle
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kBlue, Color(0xFF6CB4EE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              entry.username.isNotEmpty
                  ? entry.username[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name
          Expanded(
            child: Text(
              entry.username.isNotEmpty ? entry.username : 'Anonymous',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: _kTextPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Score pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _kBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${entry.score}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: _kBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
