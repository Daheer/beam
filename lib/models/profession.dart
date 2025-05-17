class Profession {
  final String name;
  final String icon;

  Profession({required this.name, required this.icon});

  static List<Profession> techProfessions = [
    Profession(name: 'Android Developer', icon: '🤖'),
    Profession(name: 'iOS Developer', icon: '🍎'),
    Profession(name: 'Web Developer', icon: '🌐'),
    Profession(name: 'Frontend Developer', icon: '💻'),
    Profession(name: 'Backend Developer', icon: '⚙️'),
    Profession(name: 'Full Stack Developer', icon: '🔄'),
    Profession(name: 'DevOps Engineer', icon: '🔧'),
    Profession(name: 'Data Engineer', icon: '📊'),
    Profession(name: 'Data Scientist', icon: '📈'),
    Profession(name: 'Machine Learning Engineer', icon: '🧠'),
    Profession(name: 'AI Researcher', icon: '🔍'),
    Profession(name: 'Cloud Engineer', icon: '☁️'),
    Profession(name: 'Software Engineer', icon: '🖥️'),
    Profession(name: 'Security Engineer', icon: '🔒'),
    Profession(name: 'QA Engineer', icon: '🧪'),
    Profession(name: 'UI/UX Designer', icon: '🎨'),
    Profession(name: 'Product Manager', icon: '📱'),
    Profession(name: 'Systems Architect', icon: '🏗️'),
    Profession(name: 'Blockchain Developer', icon: '⛓️'),
    Profession(name: 'Game Developer', icon: '🎮'),
  ];
}
