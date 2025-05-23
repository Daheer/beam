import 'package:flutter/material.dart';
import '../pages/professional_profile_page.dart';

class NearbyProfessionalCard extends StatefulWidget {
  const NearbyProfessionalCard({super.key, required this.info});
  final Map<String, dynamic> info;

  @override
  State<NearbyProfessionalCard> createState() => _NearbyProfessionalCardState();
}

class _NearbyProfessionalCardState extends State<NearbyProfessionalCard> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => ProfessionalProfile(professional: widget.info),
            ),
          );
        },
        child: Card(
          elevation: 0.5,
          margin: EdgeInsets.zero,
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            title: Text(
              widget.info['name'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                '${widget.info['profession']} • ${widget.info['experience']}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontSize: 12,
                ),
              ),
            ),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 48,
                height: 48,
                color: Theme.of(context).colorScheme.primaryContainer,
                child:
                    widget.info['image']?.isNotEmpty == true
                        ? Image.network(
                          widget.info['image'],
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (context, error, stackTrace) => Icon(
                                Icons.person,
                                color: Theme.of(context).colorScheme.primary,
                                size: 24,
                              ),
                        )
                        : Icon(
                          Icons.person,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.info['distance'] ?? '',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
