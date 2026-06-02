import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../analysis/session_analyzer.dart';

// ============================================================================
// App Settings: Persisted User Preferences
// ============================================================================

/// User preferences that survive app restarts: theme, mouse names, and the
/// keyboard shortcut bindings for logging chamber entries.
class AppSettings {
  AppSettings({
    required this.darkMode,
    required this.mouseIds,
    required this.keyMap,
    required this.swapOuterChambers,
  });

  final bool darkMode;
  final List<String> mouseIds;
  final Map<String, Map<Chamber, LogicalKeyboardKey>> keyMap;
  final bool swapOuterChambers;
}

// ============================================================================
// Settings Store (File-based JSON)
// ============================================================================

/// Persists [AppSettings] to a JSON file in the application documents
/// directory, mirroring the storage approach used for session history.
class SettingsStore {
  static const String _fileName = 'app_settings.json';
  static File? _file;

  static bool _darkMode = false;
  static List<String>? _mouseIds;
  static Map<String, Map<Chamber, LogicalKeyboardKey>>? _keyMap;
  static bool _swapOuterChambers = false;
  static bool _loaded = false;

  static Future<File> _getFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File(path.join(dir.path, _fileName));
    return _file!;
  }

  /// Loads persisted settings, returning defaults for anything not yet saved.
  static Future<AppSettings> load() async {
    final file = await _getFile();
    if (file.existsSync()) {
      try {
        final data = jsonDecode(await file.readAsString())
            as Map<String, dynamic>;
        _darkMode = data['darkMode'] as bool? ?? false;
        final ids = data['mouseIds'] as List<dynamic>?;
        _mouseIds = ids?.map((e) => e as String).toList();
        _keyMap = _keyMapFromJson(data['keyMap'] as Map<String, dynamic>?);
        _swapOuterChambers = data['swapOuterChambers'] as bool? ?? false;
      } catch (_) {
        // Corrupt file: fall back to defaults rather than crashing on launch.
        _darkMode = false;
        _mouseIds = null;
        _keyMap = null;
        _swapOuterChambers = false;
      }
    }
    _loaded = true;
    return AppSettings(
      darkMode: _darkMode,
      mouseIds: _mouseIds ?? const ['Mouse A', 'Mouse B', 'Mouse C'],
      keyMap: _keyMap ?? const {},
      swapOuterChambers: _swapOuterChambers,
    );
  }

  static Future<void> _save() async {
    final file = await _getFile();
    await file.writeAsString(jsonEncode({
      'darkMode': _darkMode,
      'swapOuterChambers': _swapOuterChambers,
      if (_mouseIds != null) 'mouseIds': _mouseIds,
      if (_keyMap != null) 'keyMap': _keyMapToJson(_keyMap!),
    }));
  }

  static Future<void> setSwapOuterChambers(bool value) async {
    _swapOuterChambers = value;
    if (_loaded) await _save();
  }

  static Future<void> setDarkMode(bool value) async {
    _darkMode = value;
    if (_loaded) await _save();
  }

  static Future<void> setMouseIds(List<String> ids) async {
    _mouseIds = List<String>.from(ids);
    if (_loaded) await _save();
  }

  static Future<void> setKeyMap(
    Map<String, Map<Chamber, LogicalKeyboardKey>> keyMap,
  ) async {
    _keyMap = keyMap;
    if (_loaded) await _save();
  }

  static Map<String, dynamic> _keyMapToJson(
    Map<String, Map<Chamber, LogicalKeyboardKey>> keyMap,
  ) {
    return {
      for (final mouse in keyMap.entries)
        mouse.key: {
          for (final binding in mouse.value.entries)
            binding.key.name: binding.value.keyId,
        },
    };
  }

  static Map<String, Map<Chamber, LogicalKeyboardKey>>? _keyMapFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) return null;
    final result = <String, Map<Chamber, LogicalKeyboardKey>>{};
    json.forEach((mouseId, bindings) {
      final chamberMap = <Chamber, LogicalKeyboardKey>{};
      (bindings as Map<String, dynamic>).forEach((chamberName, keyId) {
        final chamber = Chamber.values
            .where((c) => c.name == chamberName)
            .firstOrNull;
        if (chamber != null) {
          chamberMap[chamber] = LogicalKeyboardKey(keyId as int);
        }
      });
      result[mouseId] = chamberMap;
    });
    return result;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
