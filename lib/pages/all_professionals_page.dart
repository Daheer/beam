import 'package:flutter/material.dart';
import 'professional_profile_page.dart';

class AllProfessionals extends StatefulWidget {
  final List<Map<String, dynamic>> professionals;

  const AllProfessionals({super.key, required this.professionals});

  @override
  State<AllProfessionals> createState() => _AllProfessionalsState();
}

class _AllProfessionalsState extends State<AllProfessionals> {
  late List<Map<String, dynamic>> _professionals;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _professionals = List<Map<String, dynamic>>.from(widget.professionals);
  }

  Future<void> _refreshData() async {
    try {
      setState(() {
        _isRefreshing = true;
      });

      // In a real app, you would fetch fresh data here
      // For now, simulate a network delay
      await Future.delayed(const Duration(seconds: 1));

      // Keep the same list for now, in a real app this would be updated
      setState(() {
        _professionals = List<Map<String, dynamic>>.from(widget.professionals);
        _isRefreshing = false;
      });
    } catch (e) {
      print('Error refreshing data: $e');
      setState(() {
        _isRefreshing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing professionals list: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Professionals'),
        centerTitle: true,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child:
            _isRefreshing
                ? const Center(child: CircularProgressIndicator())
                : _professionals.isEmpty
                ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline_rounded,
                        size: 64,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No professionals found',
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                )
                : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:
                        MediaQuery.of(context).size.width > 600 ? 3 : 2,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _professionals.length,
                  itemBuilder: (context, index) {
                    final professional = _professionals[index];
                    return Hero(
                      tag:
                          'professional-${professional['id'] ?? professional['name'] ?? DateTime.now().millisecondsSinceEpoch}',
                      child: Material(
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => ProfessionalProfile(
                                      professional: professional,
                                    ),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.shadow.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(16),
                                  ),
                                  child: Image.network(
                                    professional['image'] ?? '',
                                    height: 140,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        height: 140,
                                        width: double.infinity,
                                        color: Colors.grey.shade300,
                                        child: const Center(
                                          child: Icon(
                                            Icons.person,
                                            size: 50,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      );
                                    },
                                    loadingBuilder: (
                                      BuildContext context,
                                      Widget child,
                                      ImageChunkEvent? loadingProgress,
                                    ) {
                                      if (loadingProgress == null) return child;
                                      return Container(
                                        height: 140,
                                        width: double.infinity,
                                        color: Colors.grey.shade100,
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            value:
                                                loadingProgress
                                                            .expectedTotalBytes !=
                                                        null
                                                    ? loadingProgress
                                                            .cumulativeBytesLoaded /
                                                        loadingProgress
                                                            .expectedTotalBytes!
                                                    : null,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        professional['name'] ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        professional['profession'] ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.secondary,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Column(
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.work_outline,
                                                size: 16,
                                                color:
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.secondary,
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  professional['experience'] ??
                                                      '',
                                                  style: TextStyle(
                                                    color:
                                                        Theme.of(
                                                          context,
                                                        ).colorScheme.secondary,
                                                    fontSize: 12,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.location_on_outlined,
                                                size: 16,
                                                color:
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.secondary,
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  professional['distance'] ??
                                                      '',
                                                  style: TextStyle(
                                                    color:
                                                        Theme.of(
                                                          context,
                                                        ).colorScheme.secondary,
                                                    fontSize: 12,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
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
    );
  }
}
