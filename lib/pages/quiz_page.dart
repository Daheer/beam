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
  int _timeLeft = 5; // Time in seconds for each question
  Timer? _timer;
  final int _passingScore = 4; // Passing score out of 5

  @override
  void initState() {
    super.initState();
    // Initialize with empty list to prevent null issues
    _questions = [];
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
        if (questions.isNotEmpty) {
          _questions = questions;
          _isLoading = false;
          _startTimer();
        } else {
          // If no questions returned, show fallback questions
          _questions = _getFallbackQuestions();
          _isLoading = false;
          _startTimer();
        }
      });
    } catch (e) {
      if (mounted) {
        // Use fallback questions if there's an error
        setState(() {
          _questions = _getFallbackQuestions();
          _isLoading = false;
        });
        _startTimer();

        SnackbarService.showError(
          context,
          message: 'Using default questions due to error: $e',
        );
      }
    }
  }

  // Provide fallback questions in case the API fails
  List<QuizQuestion> _getFallbackQuestions() {
    if (widget.profession.toLowerCase().contains('machine learning') ||
        widget.profession.toLowerCase().contains('data scientist')) {
      return [
        QuizQuestion(
          question:
              "Which of the following is a supervised learning algorithm?",
          options: ["K-Means", "PCA", "Linear Regression", "DBSCAN"],
          answer: "Linear Regression",
        ),
        QuizQuestion(
          question:
              "What metric is commonly used to evaluate classification models?",
          options: ["RMSE", "R-squared", "Accuracy", "Mean Absolute Error"],
          answer: "Accuracy",
        ),
        QuizQuestion(
          question: "What technique is used to prevent overfitting?",
          options: [
            "Feature Scaling",
            "Cross-Validation",
            "Dimensionality Reduction",
            "Data Augmentation",
          ],
          answer: "Cross-Validation",
        ),
        QuizQuestion(
          question:
              "Which library in Python is widely used for numerical operations?",
          options: ["Pandas", "Matplotlib", "NumPy", "SciPy"],
          answer: "NumPy",
        ),
        QuizQuestion(
          question: "What is the primary goal of feature scaling?",
          options: [
            "Reduce dimensionality",
            "Handle missing values",
            "Improve algorithm performance",
            "Increase data size",
          ],
          answer: "Improve algorithm performance",
        ),
      ];
    } else if (widget.profession.toLowerCase().contains('developer') ||
        widget.profession.toLowerCase().contains('engineer')) {
      return [
        QuizQuestion(
          question: "Which data structure uses LIFO ordering?",
          options: ["Queue", "Stack", "Array", "Tree"],
          answer: "Stack",
        ),
        QuizQuestion(
          question: "Which of the following is NOT a RESTful API method?",
          options: ["GET", "POST", "DELETE", "SAVE"],
          answer: "SAVE",
        ),
        QuizQuestion(
          question: "What does ORM stand for in software development?",
          options: [
            "Object-Relational Mapping",
            "Online Resource Management",
            "Operational Risk Model",
            "Object Rendering Method",
          ],
          answer: "Object-Relational Mapping",
        ),
        QuizQuestion(
          question: "Which is a core principle of functional programming?",
          options: [
            "Inheritance",
            "Immutability",
            "Polymorphism",
            "Encapsulation",
          ],
          answer: "Immutability",
        ),
        QuizQuestion(
          question: "What is the time complexity of binary search?",
          options: ["O(1)", "O(log n)", "O(n)", "O(n²)"],
          answer: "O(log n)",
        ),
      ];
    } else {
      // Default questions for other professions
      return [
        QuizQuestion(
          question: "Which of these is a version control system?",
          options: ["Docker", "Kubernetes", "Git", "Jenkins"],
          answer: "Git",
        ),
        QuizQuestion(
          question: "What does API stand for?",
          options: [
            "Application Programming Interface",
            "Advanced Programming Integration",
            "Automated Protocol Interface",
            "Application Process Integration",
          ],
          answer: "Application Programming Interface",
        ),
        QuizQuestion(
          question: "Which of these is a NoSQL database?",
          options: ["MySQL", "PostgreSQL", "MongoDB", "SQLite"],
          answer: "MongoDB",
        ),
        QuizQuestion(
          question: "Which language is primarily used for web styling?",
          options: ["HTML", "CSS", "JavaScript", "PHP"],
          answer: "CSS",
        ),
        QuizQuestion(
          question: "What is the primary purpose of a load balancer?",
          options: [
            "Distribute network traffic",
            "Store cached data",
            "Encrypt data transmission",
            "Execute server-side code",
          ],
          answer: "Distribute network traffic",
        ),
      ];
    }
  }

  void _startTimer() {
    if (_questions.isEmpty) return;

    setState(() {
      _timeLeft = 5;
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
    if (_isAnswerChecked || _isTimeUp || _questions.isEmpty) return;

    setState(() {
      _selectedAnswer = answer;
      _isAnswerChecked = true;
    });

    _timer?.cancel();
    _checkAnswer();
    Future.delayed(const Duration(seconds: 1), _moveToNextQuestion);
  }

  void _checkAnswer() {
    if (_questions.isEmpty) return;

    if (_selectedAnswer == _questions[_currentQuestionIndex].answer) {
      setState(() {
        _correctAnswers++;
      });
    }
  }

  void _moveToNextQuestion() {
    if (_questions.isEmpty) return;

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
              : _questions.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 60, color: Colors.orange),
                    const SizedBox(height: 16),
                    Text(
                      'Unable to load questions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onBackground,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'There was a problem loading questions for your profession',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onBackground,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              )
              : Container(
                color: Theme.of(context).colorScheme.background,
                child: Column(
                  children: [
                    // Timer indicator
                    LinearProgressIndicator(
                      value: _timeLeft / 5,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _timeLeft > 2 ? Colors.green : Colors.orange,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Question ${_currentQuestionIndex + 1} of ${_questions.length}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onBackground,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _questions[_currentQuestionIndex].question,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onBackground,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount:
                            _questions[_currentQuestionIndex].options.length,
                        itemBuilder: (context, index) {
                          final option =
                              _questions[_currentQuestionIndex].options[index];
                          final isSelected = _selectedAnswer == option;
                          final isCorrect =
                              option ==
                              _questions[_currentQuestionIndex].answer;
                          final showResult = _isAnswerChecked || _isTimeUp;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Material(
                              color:
                                  showResult
                                      ? isCorrect
                                          ? Colors.green.withOpacity(0.2)
                                          : isSelected
                                          ? Colors.red.withOpacity(0.2)
                                          : Theme.of(
                                            context,
                                          ).colorScheme.surfaceVariant
                                      : isSelected
                                      ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                      : Theme.of(
                                        context,
                                      ).colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                onTap: () {
                                  if (!_isAnswerChecked && !_isTimeUp) {
                                    _selectAnswer(option);
                                  }
                                },
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
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onBackground,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          option,
                                          style: TextStyle(
                                            fontSize: 16,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onBackground,
                                          ),
                                        ),
                                      ),
                                      if (showResult)
                                        Icon(
                                          isCorrect
                                              ? Icons.check_circle
                                              : (isSelected
                                                  ? Icons.cancel
                                                  : null),
                                          color:
                                              isCorrect
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
