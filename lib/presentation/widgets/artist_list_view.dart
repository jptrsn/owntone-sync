import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browse_provider.dart';
import '../screens/artist_detail_screen.dart';

class ArtistListView extends StatelessWidget {
  const ArtistListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BrowseProvider>(
      builder: (context, provider, child) {
        if (provider.artists.isEmpty) {
          return const Center(child: Text('No artists found'));
        }

        return ListView.builder(
          itemCount: provider.artists.length,
          itemBuilder: (context, index) {
            final artist = provider.artists[index];

            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(artist),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ArtistDetailScreen(artistName: artist),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
