import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SociaLyzeApp()));
}

class SociaLyzeApp extends StatelessWidget {
  const SociaLyzeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      colorSchemeSeed: Colors.indigo,
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xfff7f8fc),
    );

    return MaterialApp(
      title: 'SociaLyze',
      theme: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(
          bodyColor: const Color(0xff1f2333),
          displayColor: const Color(0xff1f2333),
        ),
      ),
      home: const _DashboardScreen(),
    );
  }
}

class Post {
  const Post({
    required this.author,
    required this.handle,
    required this.avatarColor,
    required this.content,
    required this.timestamp,
    required this.likes,
    required this.comments,
    required this.engagementRate,
    this.tags = const [],
  });

  final String author;
  final String handle;
  final Color avatarColor;
  final String content;
  final DateTime timestamp;
  final int likes;
  final int comments;
  final double engagementRate;
  final List<String> tags;
}

final postsProvider = Provider<List<Post>>((ref) {
  final now = DateTime.now();
  return [
    Post(
      author: 'Amelia Chen',
      handle: '@amelia.codes',
      avatarColor: Colors.indigo,
      content:
          'Excited to share a behind-the-scenes look at how we designed our new onboarding flow. Thread below! 🚀',
      timestamp: now.subtract(const Duration(hours: 2, minutes: 35)),
      likes: 482,
      comments: 67,
      engagementRate: 5.8,
      tags: const ['#ux', '#design', '#product'],
    ),
    Post(
      author: 'Mateo Hernández',
      handle: '@mateo.dev',
      avatarColor: Colors.orange,
      content:
          'Ran a small poll on when teams prefer async vs sync communication. Results surprised me—sharing soon!',
      timestamp: now.subtract(const Duration(hours: 6, minutes: 12)),
      likes: 256,
      comments: 32,
      engagementRate: 3.1,
      tags: const ['#remotework', '#async', '#poll'],
    ),
    Post(
      author: 'Leila Rivers',
      handle: '@leilarivs',
      avatarColor: Colors.teal,
      content:
          'New community milestone: 10k members helping each other grow every day. Grateful for this space 💙',
      timestamp: now.subtract(const Duration(days: 1, hours: 3)),
      likes: 892,
      comments: 143,
      engagementRate: 7.4,
      tags: const ['#community', '#growth'],
    ),
  ];
});

final trendingTopicsProvider = Provider<List<String>>((ref) {
  return const ['Community growth', 'Async workflows', 'UX Research'];
});

final kpiCardsProvider = Provider<List<_KpiCardData>>((ref) {
  return const [
    _KpiCardData(
      label: 'Engagement rate',
      value: '6.1%',
      trend: '+12% WoW',
      color: Color(0xff4f46e5),
    ),
    _KpiCardData(
      label: 'Top channel',
      value: 'Product Lounge',
      trend: '↑ 18% activity',
      color: Color(0xff10b981),
    ),
    _KpiCardData(
      label: 'Sentiment',
      value: '84% positive',
      trend: 'Steady this week',
      color: Color(0xfff59e0b),
    ),
  ];
});

class _KpiCardData {
  const _KpiCardData({
    required this.label,
    required this.value,
    required this.trend,
    required this.color,
  });

  final String label;
  final String value;
  final String trend;
  final Color color;
}

class _DashboardScreen extends ConsumerWidget {
  const _DashboardScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(postsProvider);
    final topics = ref.watch(trendingTopicsProvider);
    final kpis = ref.watch(kpiCardsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SociaLyze'),
        centerTitle: false,
        actions: const [
          _CircleIconButton(icon: Icons.search),
          SizedBox(width: 8),
          _CircleIconButton(icon: Icons.notifications_outlined),
          SizedBox(width: 16),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          final content = _DashboardContent(
            posts: posts,
            topics: topics,
            kpis: kpis,
            isWide: isWide,
          );

          if (!isWide) {
            return RefreshIndicator(
              onRefresh: () async {
                await Future<void>.delayed(const Duration(milliseconds: 600));
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: content,
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Center(
              child: SizedBox(
                width: 1100,
                child: SingleChildScrollView(child: content),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.posts,
    required this.topics,
    required this.kpis,
    required this.isWide,
  });

  final List<Post> posts;
  final List<String> topics;
  final List<_KpiCardData> kpis;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.symmetric(
      horizontal: isWide ? 32 : 24,
      vertical: 24,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Community intelligence dashboard',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Monitor community health, surface conversations to join, and spot trends before they peak.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey.shade700,
                    ),
              ),
            ],
          ),
        ),
        Padding(
          padding: padding,
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: kpis
                .map((kpi) => _KpiCard(
                      data: kpi,
                      width: isWide ? (1100 - 64) / 3 : double.infinity,
                    ))
                .toList(),
          ),
        ),
        Padding(
          padding: padding.copyWith(top: 12),
          child: _TrendingTopics(topics: topics),
        ),
        Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Latest conversations',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              ...posts.map((post) => _PostCard(post: post)),
            ],
          ),
        ),
        const SizedBox(height: 48),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data, required this.width});

  final _KpiCardData data;
  final double width;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(width: width, height: 150),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 12,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: data.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.trending_up,
                  color: data.color,
                ),
              ),
              const Spacer(),
              Text(
                data.value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                data.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                data.trend,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: data.color,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendingTopics extends StatelessWidget {
  const _TrendingTopics({required this.topics});

  final List<String> topics;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 12,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xff4f46e5)),
                const SizedBox(width: 8),
                Text(
                  'Trending themes',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: topics
                  .map(
                    (topic) => Chip(
                      label: Text(topic),
                      avatar: const Icon(Icons.tag, size: 18),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 16,
              spreadRadius: 4,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: post.avatarColor.withOpacity(0.2),
                    child: Text(
                      post.author[0],
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: post.avatarColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.author,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${post.handle} • ${_formatTimeAgo(post.timestamp)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.more_horiz),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                post.content,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
              ),
              if (post.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: post.tags
                      .map((tag) => Chip(
                            label: Text(tag),
                            backgroundColor: Colors.indigo.withOpacity(0.08),
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  _StatBadge(
                    icon: Icons.favorite_border,
                    label: '${post.likes} likes',
                  ),
                  const SizedBox(width: 12),
                  _StatBadge(
                    icon: Icons.mode_comment_outlined,
                    label: '${post.comments} replies',
                  ),
                  const Spacer(),
                  _EngagementPill(rate: post.engagementRate),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EngagementPill extends StatelessWidget {
  const _EngagementPill({required this.rate});

  final double rate;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.indigo.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          'Engagement ${rate.toStringAsFixed(1)}%',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xff4338ca),
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200,
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: IconButton(
            onPressed: () {},
            icon: Icon(icon, color: const Color(0xff1f2333)),
          ),
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade700),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTimeAgo(DateTime timestamp) {
  final difference = DateTime.now().difference(timestamp);
  if (difference.inMinutes < 1) {
    return 'just now';
  }
  if (difference.inMinutes < 60) {
    final minutes = difference.inMinutes;
    return '$minutes min${minutes == 1 ? '' : 's'} ago';
  }
  if (difference.inHours < 24) {
    final hours = difference.inHours;
    return '$hours hour${hours == 1 ? '' : 's'} ago';
  }
  final days = difference.inDays;
  return '$days day${days == 1 ? '' : 's'} ago';
}
