import 'package:flutter/material.dart';

class QuizResultPage extends StatelessWidget {
  final bool isPassed;
  final Function() onContinue;
  final Function() onRetake;
  final Function() onLowerExperience;

  const QuizResultPage({
    Key? key,
    required this.isPassed,
    required this.onContinue,
    required this.onRetake,
    required this.onLowerExperience,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animation or illustration
              isPassed
                  ? const Icon(
                    Icons.verified_user,
                    size: 120,
                    color: Colors.green,
                  )
                  : const Icon(
                    Icons.error_outline,
                    size: 120,
                    color: Colors.orange,
                  ),
              const SizedBox(height: 40),
              // Title
              Text(
                isPassed ? 'Verification Successful!' : 'Verification Failed',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isPassed ? Colors.green : Colors.orange,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Description
              Text(
                isPassed
                    ? 'Congratulations! You have successfully verified your professional expertise.'
                    : 'You didn\'t meet the required score for verification at this experience level.',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onBackground,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              // Action buttons
              Column(
                children: [
                  if (isPassed)
                    FilledButton(
                      onPressed: () {
                        // Pop all quiz-related pages and return to profile
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
                        // Then call the onContinue callback to update the profile
                        onContinue();
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'CONTINUE',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else ...[
                    FilledButton(
                      onPressed: onRetake,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'RETAKE QUIZ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: onLowerExperience,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        foregroundColor:
                            Theme.of(context).colorScheme.onBackground,
                        side: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.onBackground.withOpacity(0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'LOWER EXPERIENCE LEVEL',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
