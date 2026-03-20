import 'package:flutter/material.dart';

import '../models/game_state.dart';
import 'lobby_screen.dart';

class ResultScreen extends StatelessWidget {
  final GameResult result;
  final String myUserId;

  const ResultScreen({
    super.key,
    required this.result,
    required this.myUserId,
  });

  @override
  Widget build(BuildContext context) {
    final isDraw = result.result == 'draw';
    final isWinner = !isDraw && result.winner == myUserId;

    final (emoji, headline, color, points) = isDraw
        ? ('🤝', "It's a Draw!", Colors.orange, '+50')
        : isWinner
            ? ('🏆', 'You Win!', Colors.green, '+200')
            : ('😔', 'You Lose', Colors.red, '+0');

    final myMark = result.playerX == myUserId ? 'X' : 'O';
    final opponentMark = myMark == 'X' ? 'O' : 'X';
    final myName = myMark == 'X' ? result.playerXName : result.playerOName;
    final opponentName =
        opponentMark == 'X' ? result.playerXName : result.playerOName;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 80)),
                  const SizedBox(height: 16),
                  Text(
                    headline,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$points pts',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Player labels
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _PlayerLabel(
                        name: myName.isNotEmpty ? myName : 'You',
                        mark: myMark,
                        isYou: true,
                      ),
                      const Text('vs',
                          style: TextStyle(color: Colors.grey, fontSize: 14)),
                      _PlayerLabel(
                        name:
                            opponentName.isNotEmpty ? opponentName : 'Opponent',
                        mark: opponentMark,
                        isYou: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Final board
                  AspectRatio(
                    aspectRatio: 1,
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemCount: 9,
                      itemBuilder: (_, i) => _ResultBoardCell(
                        value: result.board[i],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  FilledButton.icon(
                    icon: const Icon(Icons.bolt),
                    label: const Text('Play Again'),
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const LobbyScreen()),
                        (_) => false,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const LobbyScreen()),
                        (_) => false,
                      );
                    },
                    child: const Text('Back to Lobby'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerLabel extends StatelessWidget {
  final String name;
  final String mark;
  final bool isYou;

  const _PlayerLabel({
    required this.name,
    required this.mark,
    required this.isYou,
  });

  @override
  Widget build(BuildContext context) {
    final color = mark == 'X' ? Colors.indigo : Colors.orange;
    return Column(
      children: [
        Text(
          mark,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          name,
          style: const TextStyle(fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
        if (isYou)
          Text(
            '(You)',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
      ],
    );
  }
}

class _ResultBoardCell extends StatelessWidget {
  final String value;

  const _ResultBoardCell({required this.value});

  @override
  Widget build(BuildContext context) {
    final color = value == 'X'
        ? Colors.indigo
        : value == 'O'
            ? Colors.orange
            : null;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Center(
        child: Text(
          value,
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }
}
