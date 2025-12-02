import 'dart:async';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'analysis/session_analyzer.dart';
import 'src/session_controller.dart';
import 'src/chamber_visualization.dart';
import 'src/session_database.dart';

// ============================================================================
// Extensions
// ============================================================================

extension on Protocol {
  String get label {
    switch (this) {
      case Protocol.socialInteraction:
        return 'Social Interaction';
      case Protocol.socialNovelty:
        return 'Social Novelty';
    }
  }
}

// ============================================================================
// Global State & Constants
// ============================================================================

/// Dark mode provider for app-wide theme control
final darkModeProvider = StateProvider<bool>((ref) => false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  
  // Initialize window manager and set minimum size
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    minimumSize: Size(1400, 900),
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  
  runApp(const ProviderScope(child: SociaLyzeApp()));
}

class SociaLyzeApp extends ConsumerWidget {
  const SociaLyzeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(darkModeProvider);
    
    return MaterialApp(
      title: 'SociaLyze',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const SessionHome(),
    );
  }
}

/// Global mutable list of mouse IDs for naming and key binding.
/// Updated via the "Rename mice" dialog.
List<String> _mouseIds = ['Mouse A', 'Mouse B', 'Mouse C'];

/// Ordered list of chamber types for consistent UI display.
const List<Chamber> _chamberOrder = [
  Chamber.empty,
  Chamber.middle,
  Chamber.stranger,
];

// ============================================================================
// Keyboard Shortcut Configuration
// ============================================================================

/// Builds default key bindings for each mouse and chamber.
/// Maps numpad keys to mice/chambers:
/// - Mouse A: 7/4/1 (empty/middle/stranger)
/// - Mouse B: 8/5/2 (empty/middle/stranger)
/// - Mouse C: 9/6/3 (empty/middle/stranger)
Map<String, Map<Chamber, LogicalKeyboardKey>> _defaultKeyMap() {
  const keyGrid = <List<LogicalKeyboardKey>>[
    [
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad1,
    ],
    [
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad2,
    ],
    [
      LogicalKeyboardKey.numpad9,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad3,
    ],
  ];

  final map = <String, Map<Chamber, LogicalKeyboardKey>>{};
  for (var mouseIndex = 0; mouseIndex < _mouseIds.length; mouseIndex++) {
    final chambers = <Chamber, LogicalKeyboardKey>{};
    for (var chamberIndex = 0;
        chamberIndex < _chamberOrder.length;
        chamberIndex++) {
      chambers[_chamberOrder[chamberIndex]] = keyGrid[mouseIndex][chamberIndex];
    }
    map[_mouseIds[mouseIndex]] = chambers;
  }
  return map;
}

/// Deep clones key mappings for modification.
Map<String, Map<Chamber, LogicalKeyboardKey>> _cloneKeyMap(
  Map<String, Map<Chamber, LogicalKeyboardKey>> map,
) {
  return {
    for (final entry in map.entries)
      entry.key: Map<Chamber, LogicalKeyboardKey>.from(entry.value),
  };
}

// ============================================================================
// Session Home Screen
// ============================================================================

class SessionHome extends ConsumerStatefulWidget {
  const SessionHome({super.key});

  @override
  ConsumerState<SessionHome> createState() => _SessionHomeState();
}

class _SessionHomeState extends ConsumerState<SessionHome> {
  final FocusNode _keyboardFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _keyboardFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final controller = ref.read(sessionControllerProvider.notifier);
    final bindings = _buildKeyBindings(session);
    final bindingLookup = {
      for (final binding in bindings) binding.key: binding,
    };

    return KeyboardListener(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is! KeyDownEvent ||
            HardwareKeyboard.instance.isAltPressed ||
            HardwareKeyboard.instance.isControlPressed) {
          return;
        }
        final binding = bindingLookup[event.logicalKey];
        if (binding == null) {
          return;
        }
        controller.logEvent(binding.mouseId, binding.chamber);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SociaLyze 3 Chamber Test Helper'),
          actions: [
            if (session.isRecording)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.fiber_manual_record, color: Colors.red),
                    const SizedBox(width: 6),
                    Text(
                      'Recording…',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.red),
                    ),
                  ],
                ),
              ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SessionToolbar(session: session, controller: controller),
              const SizedBox(height: 24),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _VideoPanel(
                          session: session, controller: controller),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 2,
                      child: _EventLog(session: session),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          Expanded(
                            child: _SummaryPanel(session: session),
                          ),
                          const SizedBox(height: 24),
                          Expanded(
                            child: _SessionHistoryPanel(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _KeyboardLegend(
                    protocol: session.protocol, bindings: bindings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Toolbar Widget: Control Recording, Protocol, Export & Settings
// ============================================================================

class _SessionToolbar extends ConsumerWidget {
  const _SessionToolbar({required this.session, required this.controller});

  final SessionState session;
  final SessionController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(darkModeProvider);
    return Wrap(
      spacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 12,
      children: [
        DropdownButton<Protocol>(
          value: session.protocol,
          onChanged: session.isRecording
              ? null
              : (value) {
                  if (value != null) {
                    controller.setProtocol(value);
                  }
                },
          items: Protocol.values
              .map(
                (protocol) => DropdownMenuItem(
                  value: protocol,
                  child: Text(protocol.label),
                ),
              )
              .toList(),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start session'),
          onPressed: session.isRecording ? null : controller.startSession,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.stop),
          label: const Text('Stop session'),
          onPressed: session.isRecording
              ? () async {
                  await controller.stopSession();
                  ref.invalidate(sessionHistoryProvider);
                }
              : null,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear events'),
          onPressed: session.events.isEmpty && !session.isRecording
              ? null
              : controller.clearSession,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.keyboard),
          label: const Text('Remap shortcuts'),
          onPressed: session.isRecording
              ? null
              : () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => _RemapKeysDialog(
                      session: session,
                      controller: controller,
                    ),
                  );
                },
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.table_view),
          label: const Text('Export Summary'),
          onPressed: session.summary == null
              ? null
              : () async {
                  final success = await controller.exportSummaryToFile();
                  if (!context.mounted) return;
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? 'Summary exported successfully'
                            : 'Export cancelled or failed',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
        ),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit),
            label: const Text('Rename mice'),
            onPressed: session.isRecording
                ? null
                : () {
                    showDialog<void>(
                      context: context,
                      builder: (context) => _RenameMouseDialog(
                        session: session,
                        controller: controller,
                      ),
                    );
                  },
          ),
        if (session.startedAt != null)
          Text(
            'Started at: ${_formatTime(session.startedAt!)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        IconButton(
          icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
          tooltip: isDarkMode ? 'Light Mode' : 'Dark Mode',
          onPressed: () {
            ref.read(darkModeProvider.notifier).state = !isDarkMode;
          },
        ),
      ],
    );
  }
}

// ============================================================================
// Video Panel: Media Playback & File Selection
// ============================================================================

class _VideoPanel extends StatefulWidget {
  const _VideoPanel({required this.session, required this.controller});
  final SessionState session;
  final SessionController controller;

  @override
  State<_VideoPanel> createState() => _VideoPanelState();
}

class _VideoPanelState extends State<_VideoPanel> {
  bool _dragging = false;
  bool _opening = false;
  double _rate = 1.0;

  // Player + controller
  late final Player _player = Player();
  late final VideoController _videoController = VideoController(_player);

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _open(String path) async {
    setState(() => _opening = true);
    try {
      await _player.open(Media(path));
      await _player.setRate(_rate); // ensure current speed applies
      widget.controller.attachVideo(path);
      
      // Small delay to ensure texture is properly sized before showing
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        setState(() {}); // Force rebuild to ensure video is displayed
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoPath = widget.session.videoPath;

    return Card(
      elevation: 2,
      clipBehavior: Clip.none,
      child: Column(
        children: [
          Expanded(
            child: DropTarget(
              onDragEntered: (_) => setState(() => _dragging = true),
              onDragExited: (_) => setState(() => _dragging = false),
              onDragDone: (details) {
                final file = details.files.firstOrNull;
                if (file?.path != null) _open(file!.path);
                setState(() => _dragging = false);
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (videoPath != null)
                    Container(
                      key: ValueKey(videoPath),
                      color: Colors.black,
                      child: SizedBox.expand(
                        child: Video(
                          controller: _videoController,
                          fit: BoxFit.contain,
                        ),
                      ),
                    )
                  else
                    Container(
                      color: _dragging
                          ? Colors.indigo.withValues(alpha: 0.08)
                          : Colors.black,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.video_library_outlined,
                                        size: 64, color: Colors.white),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Drop a video file to play (AVI/MP4)',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(color: Colors.white),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'May need to drag video twice for visual playback',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.white70),
                                    ),
                                    const SizedBox(height: 12),
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        child: Text(
                                          widget.session.isRecording
                                              ? 'Logging active'
                                              : 'Ready to record',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  if (_opening)
                    Container(
                      color: Colors.black54,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonal(
                  onPressed: () => _player.play(),
                  child: const Icon(Icons.play_arrow),
                ),
                FilledButton.tonal(
                  onPressed: () => _player.pause(),
                  child: const Icon(Icons.pause),
                ),
                FilledButton.tonal(
                  onPressed: () async {
                    final next = (_rate - 0.25).clamp(0.25, 4.0);
                    setState(() => _rate = next);
                    await _player.setRate(next);
                  },
                  child: const Text('- speed'),
                ),
                FilledButton.tonal(
                  onPressed: () async {
                    final next = (_rate + 0.25).clamp(0.25, 4.0);
                    setState(() => _rate = next);
                    await _player.setRate(next);
                  },
                  child: const Text('+ speed'),
                ),

                Chip(label: Text('Speed: x${_rate.toStringAsFixed(2)}')),

                if (videoPath != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Tooltip(
                      message: videoPath,
                      child: Text(
                        videoPath.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Event Log: Real-time Event Display During Recording
// ============================================================================

class _EventLog extends StatelessWidget {
  const _EventLog({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final events = session.events.reversed.toList();
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Event log',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: events.isEmpty
                  ? _EmptyState(
                      message: session.isRecording
                          ? 'Press the mapped keys to log chamber entries.'
                          : 'Start a session to begin logging entries.',
                    )
                  : ListView.separated(
                      itemCount: events.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final event = events[index];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            child: Text(event.mouseId.split(' ').last),
                          ),
                          title: Text(
                            '${event.mouseId} → ${_chamberLabel(session.protocol, event.chamber)}',
                          ),
                          subtitle: Text(_formatTime(event.timestamp)),
                          trailing: Chip(
                            label: Text(
                                _chamberLabel(session.protocol, event.chamber)),
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

// ============================================================================
// Summary Panel: Post-Session Analytics & Visualization
// ============================================================================

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final summary = session.summary;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Session analytics',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (summary == null)
              Expanded(
                child: _EmptyState(
                  message: session.isRecording
                      ? 'Stop the session to generate dwell-time summaries.'
                      : 'No analytics yet. Record a session and stop logging to compute summaries.',
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Duration: ${_formatDuration(summary.duration)}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      ...summary.mouseSummaries.entries.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Chamber visualization for this mouse
                              SizedBox(
                                height: 300,
                                width: double.infinity,
                                child: Card(
                                  elevation: 1,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: ChamberVisualization(
                                      summary: entry.value,
                                      protocol: session.protocol,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _MouseSummaryCard(
                                mouseId: entry.key,
                                summary: entry.value,
                                protocol: session.protocol,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Mouse Summary Card: Per-Mouse Chamber Dwell Stats
// ============================================================================

class _MouseSummaryCard extends StatelessWidget {
  const _MouseSummaryCard({
    required this.mouseId,
    required this.summary,
    required this.protocol,
  });

  final String mouseId;
  final MouseSummary summary;
  final Protocol protocol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mouseId,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: Chamber.values.map((chamber) {
                final dwell = summary.dwellTime(chamber);
                return Chip(
                  label: Text(
                    '${_chamberLabel(protocol, chamber)}: ${_formatDuration(dwell)}',
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Text('Switches: ${summary.switchCount}'),
            Text('Total dwell: ${_formatDuration(summary.totalDwell)}'),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Keyboard Legend: Visual Reference for Key Bindings
// ============================================================================

class _KeyboardLegend extends StatelessWidget {
  const _KeyboardLegend({required this.protocol, required this.bindings});

  final Protocol protocol;
  final List<_KeyBinding> bindings;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<_KeyBinding>>{};
    for (final binding in bindings) {
      grouped.putIfAbsent(binding.mouseId, () => []).add(binding);
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Keyboard shortcuts (${protocol.label})',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                spacing: 24,
                runSpacing: 12,
                children: grouped.entries.map((entry) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.key,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      ...entry.value.map(
                        (binding) => Text(
                          '${binding.keyLabel} → ${_chamberLabel(protocol, binding.chamber)}',
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Session History Panel: View & Delete Previous Sessions
// ============================================================================

class _SessionHistoryPanel extends ConsumerWidget {
  const _SessionHistoryPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(sessionHistoryProvider);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Session history',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: historyAsync.when(
                data: (sessions) {
                  if (sessions.isEmpty) {
                    return _EmptyState(message: 'No sessions recorded yet.');
                  }
                  return ListView.separated(
                    itemCount: sessions.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final session = sessions[sessions.length - 1 - index];
                      return _SessionHistoryItem(session: session);
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stack) => Center(
                  child: Text('Error loading history: $error'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Session History Item: Individual Session Record
// ============================================================================

class _SessionHistoryItem extends ConsumerWidget {
  const _SessionHistoryItem({required this.session});

  final SessionHistoryEntry session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeStr =
        '${session.startedAt.hour.toString().padLeft(2, '0')}:${session.startedAt.minute.toString().padLeft(2, '0')}';
    final durationStr = _formatDuration(session.duration);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.protocol,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '$timeStr • $durationStr • ${session.mouseCount} mice',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                child: const Text('Delete'),
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete session?'),
                      content: Text(
                        'Delete session from ${session.startedAt.toLocal()}?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    await SessionHistoryDatabase.deleteSession(session.id);
                    if (context.mounted) {
                      ref.invalidate(sessionHistoryProvider);
                    }
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Remap Keys Dialog: Interactive Key Binding Configuration
// ============================================================================

class _RemapKeysDialog extends StatefulWidget {
  const _RemapKeysDialog({required this.session, required this.controller});

  final SessionState session;
  final SessionController controller;

  @override
  State<_RemapKeysDialog> createState() => _RemapKeysDialogState();
}

class _RemapKeysDialogState extends State<_RemapKeysDialog> {
  _RemapKeysDialogState();

  late Map<String, Map<Chamber, LogicalKeyboardKey>> _workingMap;
  String? _listeningMouseId;
  Chamber? _listeningChamber;
  String? _error;
  final FocusNode _focusNode = FocusNode();

  late final Player _player = Player();

  bool get _isListening => _listeningMouseId != null && _listeningChamber != null;

  @override
  void initState() {
    super.initState();
    _workingMap = _cloneKeyMap(widget.session.keyMap);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _player.dispose();
    super.dispose();
  }

  void _startListening(String mouseId, Chamber chamber) {
    setState(() {
      _listeningMouseId = mouseId;
      _listeningChamber = chamber;
      _error = null;
    });
    _focusNode.requestFocus();
  }

  void _stopListening() {
    if (!_isListening && _error == null) {
      return;
    }
    setState(() {
      _listeningMouseId = null;
      _listeningChamber = null;
      _error = null;
    });
  }

  _BindingTarget? _findConflict(
    LogicalKeyboardKey key,
    _BindingTarget target,
  ) {
    for (final entry in _workingMap.entries) {
      for (final chamberEntry in entry.value.entries) {
        if (entry.key == target.mouseId && chamberEntry.key == target.chamber) {
          continue;
        }
        if (chamberEntry.value == key) {
          return _BindingTarget(entry.key, chamberEntry.key);
        }
      }
    }
    return null;
  }

  void _handleKey(KeyEvent event) {
    if (!_isListening || event is! KeyDownEvent) {
      return;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      _stopListening();
      return;
    }

    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        _isModifierKey(key)) {
      return;
    }

    final target = _BindingTarget(_listeningMouseId!, _listeningChamber!);
    final conflict = _findConflict(key, target);
    if (conflict != null) {
      setState(() {
        _error =
            'Already assigned to ${conflict.mouseId} → ${_chamberLabel(widget.session.protocol, conflict.chamber)}';
      });
      return;
    }

    final mouseBindings = _workingMap[target.mouseId];
    if (mouseBindings == null) {
      _stopListening();
      return;
    }

    setState(() {
      mouseBindings[target.chamber] = key;
      _listeningMouseId = null;
      _listeningChamber = null;
      _error = null;
    });
  }

  bool _isListeningFor(String mouseId, Chamber chamber) {
    return _listeningMouseId == mouseId && _listeningChamber == chamber;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Remap shortcuts'),
      content: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assign the key you want to use for each mouse and chamber. Keys must be unique.',
                style: theme.textTheme.bodyMedium,
              ),
              if (_isListening) ...[
                const SizedBox(height: 12),
                Text(
                  'Listening… press a key to update the shortcut, or press Esc to cancel.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 280,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final mouseId in _mouseIds)
                      if (_workingMap.containsKey(mouseId))
                        _KeyRemapSection(
                          mouseId: mouseId,
                          protocol: widget.session.protocol,
                          entries: _workingMap[mouseId]!,
                          onTap: _startListening,
                          onCancel: _stopListening,
                          isListening: _isListeningFor,
                        ),
                    for (final entry in _workingMap.entries)
                      if (!_mouseIds.contains(entry.key))
                        _KeyRemapSection(
                          mouseId: entry.key,
                          protocol: widget.session.protocol,
                          entries: entry.value,
                          onTap: _startListening,
                          onCancel: _stopListening,
                          isListening: _isListeningFor,
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            _stopListening();
            setState(() {
              _workingMap = _defaultKeyMap();
            });
          },
          child: const Text('Reset to defaults'),
        ),
        FilledButton(
          onPressed: () {
            widget.controller.setKeyBindings(_workingMap);
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ============================================================================
// Key Remap Section: Per-Mouse Key Binding Interface
// ============================================================================

class _KeyRemapSection extends StatelessWidget {
  const _KeyRemapSection({
    required this.mouseId,
    required this.protocol,
    required this.entries,
    required this.onTap,
    required this.onCancel,
    required this.isListening,
  });

  final String mouseId;
  final Protocol protocol;
  final Map<Chamber, LogicalKeyboardKey> entries;
  final void Function(String mouseId, Chamber chamber) onTap;
  final VoidCallback onCancel;
  final bool Function(String mouseId, Chamber chamber) isListening;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mouseId,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ..._chamberOrder.map((chamber) {
            final key = entries[chamber];
            if (key == null) {
              return const SizedBox.shrink();
            }
            final listening = isListening(mouseId, chamber);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_chamberLabel(protocol, chamber)),
              subtitle: Text('Shortcut: ${_describeKey(key)}'),
              trailing: OutlinedButton(
                onPressed: listening ? onCancel : () => onTap(mouseId, chamber),
                child: Text(listening ? 'Cancel' : 'Change'),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _BindingTarget {
  const _BindingTarget(this.mouseId, this.chamber);

  final String mouseId;
  final Chamber chamber;
}

// ============================================================================
// Empty State: Placeholder Message Widgets
// ============================================================================

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(color: Colors.grey.shade600),
      ),
    );
  }
}

class _KeyBinding {
  const _KeyBinding({
    required this.key,
    required this.keyLabel,
    required this.mouseId,
    required this.chamber,
  });

  final LogicalKeyboardKey key;
  final String keyLabel;
  final String mouseId;
  final Chamber chamber;
}

List<_KeyBinding> _buildKeyBindings(SessionState session) {
  final bindings = <_KeyBinding>[];
  final seen = <String>{};

  void addBindingsFor(String mouseId, Map<Chamber, LogicalKeyboardKey>? map) {
    if (map == null) {
      return;
    }
    for (final chamber in _chamberOrder) {
      final key = map[chamber];
      if (key == null) {
        continue;
      }
      bindings.add(
        _KeyBinding(
          key: key,
          keyLabel: _describeKey(key),
          mouseId: mouseId,
          chamber: chamber,
        ),
      );
    }
    seen.add(mouseId);
  }

  for (final mouseId in _mouseIds) {
    addBindingsFor(mouseId, session.keyMap[mouseId]);
  }

  for (final entry in session.keyMap.entries) {
    if (seen.contains(entry.key)) {
      continue;
    }
    addBindingsFor(entry.key, entry.value);
  }

  return bindings;
}

String _describeKey(LogicalKeyboardKey key) {
  final debugName = key.debugName;
  if (debugName != null && debugName.isNotEmpty) {
    if (debugName.startsWith('Key ') && debugName.length == 5) {
      return debugName.substring(4);
    }
    if (debugName.startsWith('Digit ') && debugName.length == 7) {
      return debugName.substring(6);
    }
    return debugName;
  }

  final label = key.keyLabel;
  if (label.isNotEmpty) {
    return label.length == 1 ? label.toUpperCase() : label;
  }

  return 'Key ${key.keyId.toRadixString(16)}';
}

bool _isModifierKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight ||
      key == LogicalKeyboardKey.capsLock ||
      key == LogicalKeyboardKey.numLock ||
      key == LogicalKeyboardKey.scrollLock ||
      key == LogicalKeyboardKey.fn;
}

String _chamberLabel(Protocol protocol, Chamber chamber) {
  switch (protocol) {
    case Protocol.socialInteraction:
      switch (chamber) {
        case Chamber.empty:
          return 'Empty';
        case Chamber.middle:
          return 'Middle';
        case Chamber.stranger:
          return 'Stranger';
      }
    case Protocol.socialNovelty:
      switch (chamber) {
        case Chamber.empty:
          return 'New Stranger';
        case Chamber.middle:
          return 'Middle';
        case Chamber.stranger:
          return 'Stranger';
      }
  }
}

String _formatTime(DateTime timestamp) {
  final timeOfDay = TimeOfDay.fromDateTime(timestamp);
  final hour = timeOfDay.hourOfPeriod == 0 ? 12 : timeOfDay.hourOfPeriod;
  final minute = timeOfDay.minute.toString().padLeft(2, '0');
  final suffix = timeOfDay.period == DayPeriod.am ? 'AM' : 'PM';
  return '$hour:$minute $suffix';
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  final buffer = StringBuffer();
  if (hours > 0) {
    buffer.write(hours.toString().padLeft(2, '0'));
    buffer.write('h ');
  }
  buffer.write(minutes.toString().padLeft(2, '0'));
  buffer.write('m ');
  buffer.write(seconds.toString().padLeft(2, '0'));
  buffer.write('s');
  return buffer.toString();
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// ============================================================================
// Rename Mouse Dialog: Interactive Mouse ID Editor
// ============================================================================

class _RenameMouseDialog extends StatefulWidget {
  const _RenameMouseDialog({required this.session, required this.controller});

  final SessionState session;
  final SessionController controller;

  @override
  State<_RenameMouseDialog> createState() => _RenameMouseDialogState();
}

class _RenameMouseDialogState extends State<_RenameMouseDialog> {
  late Map<int, String> _newNames;
  late Map<int, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _newNames = {for (var i = 0; i < _mouseIds.length; i++) i: _mouseIds[i]};
    // Create one TextEditingController per mouse field, initialized with current name
    _controllers = {
      for (var i = 0; i < _mouseIds.length; i++)
        i: TextEditingController(text: _mouseIds[i])
    };
  }

  @override
  void dispose() {
    // Clean up controllers when dialog closes
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Rename mice'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter new names for each mouse:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ..._mouseIds.asMap().entries.map((entry) {
              final index = entry.key;
              final currentName = entry.value;
              final controller = _controllers[index]!;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: controller,
                  onChanged: (value) {
                    setState(() => _newNames[index] = value);
                  },
                  decoration: InputDecoration(
                    labelText: currentName,
                    hintText: currentName,
                    border: const OutlineInputBorder(),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            // Update the mutable _mouseIds list with controller values
            for (var i = 0; i < _mouseIds.length; i++) {
              final newName = _controllers[i]?.text.trim();
              if (newName != null && newName.isNotEmpty) {
                _mouseIds[i] = newName;
              }
            }

            // Update key mappings with new names
            final updatedKeyMap = <String, Map<Chamber, LogicalKeyboardKey>>{};
            for (var i = 0; i < _mouseIds.length; i++) {
              final oldId = ['Mouse A', 'Mouse B', 'Mouse C'][i];
              final newId = _mouseIds[i];
              final bindings = widget.session.keyMap[oldId];
              if (bindings != null) {
                updatedKeyMap[newId] = Map.from(bindings);
              }
            }

            widget.controller.setKeyBindings(updatedKeyMap);
            Navigator.of(context).pop();
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
