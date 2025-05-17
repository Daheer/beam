import 'dart:async';
import 'package:flutter/material.dart';
import '../services/quiz_service.dart';
import '../services/snackbar_service.dart';

class QuizPage extends StatefulWidget {
  final String profession;
  final int experience;
  final Function(bool isPassed) onQuizComplete;

  const QuizPage({
    Key? key,
    required this.profession,
    required this.experience,
    required this.onQuizComplete,
  }) : super(key: key);

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late List<QuizQuestion> _questions;
  bool _isLoading = true;
  int _currentQuestionIndex = 0;
  int _correctAnswers = 0;
  String? _selectedAnswer;
  bool _isAnswerChecked = false;
  bool _isTimeUp = false;
  int _timeLeft = 10; // Time in seconds for each question
  Timer? _timer;
  final int _passingScore = 4; // Passing score out of 5

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    try {
      final questions = await QuizService.fetchQuestions(
        widget.profession,
        widget.experience,
      );
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
      _startTimer();
    } catch (e) {
      if (mounted) {
        SnackbarService.showError(
          context,
          message: 'Error loading questions: $e',
        );
      }
    }
  }

  void _startTimer() {
    setState(() {
      _timeLeft = 10;
      _isTimeUp = false;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 0) {
        setState(() {
          _timeLeft--;
        });
      } else {
        timer.cancel();
        setState(() {
          _isTimeUp = true;
          _isAnswerChecked = true;
        });

        // Check if answer was correct and move to next question after a delay
        _checkAnswer();
        Future.delayed(const Duration(seconds: 1), _moveToNextQuestion);
      }
    });
  }

  void _selectAnswer(String answer) {
    if (_isAnswerChecked || _isTimeUp) return;

    setState(() {
      _selectedAnswer = answer;
      _isAnswerChecked = true;
    });

    _timer?.cancel();
    _checkAnswer();
    Future.delayed(const Duration(seconds: 1), _moveToNextQuestion);
  }

  void _checkAnswer() {
    if (_selectedAnswer == _questions[_currentQuestionIndex].answer) {
      setState(() {
        _correctAnswers++;
      });
    }
  }

  void _moveToNextQuestion() {
    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
        _selectedAnswer = null;
        _isAnswerChecked = false;
        _isTimeUp = false;
      });
      _startTimer();
    } else {
      // Quiz is complete
      final isPassed = _correctAnswers >= _passingScore;
      widget.onQuizComplete(isPassed);
    }
  }

  Color _getOptionColor(String option) {
    if (!_isAnswerChecked && !_isTimeUp) {
      return option == _selectedAnswer
          ? Colors.blue.shade100
          : Colors.grey.shade100;
    }

    final correctAnswer = _questions[_currentQuestionIndex].answer;

    if (option == correctAnswer) {
      return Colors.green.shade100;
    } else if (option == _selectedAnswer) {
      return Colors.red.shade100;
    } else {
      return Colors.grey.shade100;
    }
  }

  Widget _buildProgressBar() {
    return Row(
      children: [
        Text('${_currentQuestionIndex + 1}/${_questions.length}'),
        const SizedBox(width: 8),
        Expanded(
          child: LinearProgressIndicator(
            value: (_currentQuestionIndex + 1) / _questions.length,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimer() {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          height: 50,
          width: 50,
          child: CircularProgressIndicator(
            value: _timeLeft / 5,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              _timeLeft > 2 ? Colors.green : Colors.red,
            ),
            strokeWidth: 5,
          ),
        ),
        Text(
          '$_timeLeft',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge Verification'),
        centerTitle: true,
      ),
      body:
          _isLoading
              ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading quiz questions...'),
                  ],
                ),
              )
              : Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildProgressBar(),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Score: $_correctAnswers/${_currentQuestionIndex + (_isAnswerChecked ? 1 : 0)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _buildTimer(),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          _questions[_currentQuestionIndex].question,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: ListView.builder(
                        itemCount:
                            _questions[_currentQuestionIndex].options.length,
                        itemBuilder: (context, index) {
                          final option =
                              _questions[_currentQuestionIndex].options[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Material(
                              color: _getOptionColor(option),
                              borderRadius: BorderRadius.circular(12),
                              elevation: option == _selectedAnswer ? 4 : 2,
                              child: InkWell(
                                onTap:
                                    _isAnswerChecked || _isTimeUp
                                        ? null
                                        : () => _selectAnswer(option),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16.0,
                                    horizontal: 16.0,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        '${String.fromCharCode(65 + index)}.',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          option,
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                      ),
                                      if (_isAnswerChecked || _isTimeUp)
                                        Icon(
                                          option ==
                                                  _questions[_currentQuestionIndex]
                                                      .answer
                                              ? Icons.check_circle
                                              : (option == _selectedAnswer
                                                  ? Icons.cancel
                                                  : null),
                                          color:
                                              option ==
                                                      _questions[_currentQuestionIndex]
                                                          .answer
                                                  ? Colors.green
                                                  : Colors.red,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}
