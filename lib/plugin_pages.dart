import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'finance_widgets.dart';
import 'greenhouse_client.dart';
import 'greenhouse_theme.dart';

/// Component capability tokens advertised when negotiating UI pages.
///
/// The server projects a page only when it can render every component in the
/// page. Keeping this list host-owned means a new page needs no app release.
const pluginComponentCapabilities = [
  'section.v1',
  'text.v1',
  'notice.v1',
  'image.v1',
  'facts.v1',
  'collection.v1',
  'search.v1',
  'form.v1',
  'button.v1',
  'collection-detail.v1',
  'link.v1',
  'picker.v1',
  'dialog.v1',
  'disclosure.v1',
];

const pluginUiVersions = '1,2';

Map<String, String> get _negotiation => {
  'versions': pluginUiVersions,
  'capabilities': pluginComponentCapabilities.join(','),
  'surface': 'mobile',
};

List<Json> pluginItems(Object? data) {
  if (data is List) return objects(data);
  if (data is Map) return objects(data['items']);
  return const [];
}

bool pluginHasMore(Object? data) => data is Map && data['hasMore'] == true;

String pluginPagePath(String installationId, String pageId) =>
    '/plugins/${Uri.encodeComponent(installationId)}/pages/${Uri.encodeComponent(pageId)}';

String normalizePluginPath(String value) {
  final trimmed = value.trim();
  if (trimmed.length > 1 && trimmed.endsWith('/')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

@immutable
class PluginPageEntry {
  const PluginPageEntry({
    required this.installationId,
    required this.pageId,
    required this.title,
    required this.path,
    required this.icon,
    required this.version,
    required this.availability,
    required this.requiredCapabilities,
    required this.legacyPaths,
    this.description,
    this.revision = '',
  });

  final String installationId;
  final String pageId;
  final String title;
  final String? description;
  final String revision;
  final String path;
  final String icon;
  final int version;
  final String availability;
  final List<String> requiredCapabilities;
  final List<String> legacyPaths;

  bool get available => availability == 'available';

  static PluginPageEntry? fromJson(Object? value) {
    final row = object(value);
    final installationId = label(row['installationId'], '');
    final pageId = label(row['pageId'], '');
    final title = label(row['title'], '');
    if (installationId.isEmpty || pageId.isEmpty || title.isEmpty) return null;
    final path = normalizePluginPath(
      label(row['path'], pluginPagePath(installationId, pageId)),
    );
    final version = row['version'] == 1 || row['version'] == 2
        ? row['version'] as int
        : 0;
    return PluginPageEntry(
      installationId: installationId,
      pageId: pageId,
      title: title,
      revision: label(row['revision'], ''),
      description: row['description'] is String
          ? (row['description'] as String).trim()
          : null,
      path: path,
      icon: label(row['icon'], 'extension'),
      version: version,
      availability: label(row['availability'], 'available'),
      requiredCapabilities: row['requiredCapabilities'] is List
          ? (row['requiredCapabilities'] as List).whereType<String>().toList()
          : const [],
      legacyPaths: row['legacyPaths'] is List
          ? (row['legacyPaths'] as List)
                .whereType<String>()
                .map(normalizePluginPath)
                .toList()
          : const [],
    );
  }
}

@immutable
class PluginNavigation {
  const PluginNavigation(this.pages);

  final List<PluginPageEntry> pages;

  static PluginNavigation fromJson(Json json) => PluginNavigation(
    objects(json['pages'])
        .map(PluginPageEntry.fromJson)
        .whereType<PluginPageEntry>()
        .toList(),
  );

  PluginPageEntry? byPath(String? path) {
    final wanted = path == null ? null : normalizePluginPath(path);
    if (wanted == null) return null;
    return pages.where((page) => page.path == wanted).firstOrNull;
  }

  PluginPageEntry? byLegacyPath(String? path) {
    final wanted = path == null ? null : normalizePluginPath(path);
    if (wanted == null) return null;
    return pages.where((page) => page.legacyPaths.contains(wanted)).firstOrNull;
  }

  /// Resolves a stored/deep-link path to a live generic page path.
  ///
  /// Legacy aliases such as `/cards` move through the navigation response's
  /// `legacyPaths`; no client source ever names the Cards plugin.
  String? resolvePath(String? saved) {
    final wanted = saved == null ? null : normalizePluginPath(saved);
    if (wanted == null) return null;
    return byPath(wanted)?.path ?? byLegacyPath(wanted)?.path;
  }
}

Future<PluginNavigation> fetchPluginNavigation(GreenhouseClient client) async {
  final response = await client.request(
    '/ui/navigation',
    query: {
      'versions': pluginUiVersions,
      'capabilities': pluginComponentCapabilities.join(','),
      'surface': 'mobile',
    },
  );
  return PluginNavigation.fromJson(response);
}

@immutable
class PluginResourceState {
  const PluginResourceState({required this.data, required this.revision});

  final Object? data;
  final String revision;
}

@immutable
class PluginPageDocument {
  const PluginPageDocument({
    required this.installationId,
    required this.pageId,
    required this.title,
    required this.ui,
    required this.resources,
    required this.readOnly,
  });

  final String installationId;
  final String pageId;
  final String title;
  final Json ui;
  final Map<String, PluginResourceState> resources;
  final bool readOnly;

  static PluginPageDocument fromJson(Json json) {
    final resources = <String, PluginResourceState>{};
    for (final entry in object(json['resources']).entries) {
      final value = object(entry.value);
      resources[entry.key] = PluginResourceState(
        data: value['data'],
        revision: label(value['revision'], ''),
      );
    }
    return PluginPageDocument(
      installationId: label(json['installationId'], ''),
      pageId: label(json['pageId'], ''),
      title: label(json['title'], ''),
      ui: object(json['ui']),
      resources: resources,
      readOnly: json['readOnly'] == true,
    );
  }
}

@immutable
class PluginQueryResult {
  const PluginQueryResult({required this.data, required this.revision});

  final Object? data;
  final String revision;
}

@immutable
class PluginMutationResult {
  const PluginMutationResult({
    required this.data,
    required this.revision,
    required this.invalidatedResources,
  });

  final Object? data;
  final String revision;
  final List<String> invalidatedResources;
}

/// Transport boundary for one dynamic page.
///
/// The renderer never builds URLs or reads provider details. Tests can supply a
/// small in-memory transport instead of a server.
abstract class PluginPageTransport {
  Future<PluginPageDocument> loadPage();

  Future<PluginQueryResult> runQuery(String queryId, Json input);

  Future<PluginMutationResult> runAction(
    String actionId,
    Json input, {
    String? revision,
  });
}

class ClientPluginPageTransport implements PluginPageTransport {
  ClientPluginPageTransport({required this.client, required this.entry})
    : _scope =
          client.identity?.preferenceScope(client.origin) ??
          client.origin?.toString();

  final String? _scope;

  final GreenhouseClient client;
  final PluginPageEntry entry;

  @override
  bool operator ==(Object other) =>
      other is ClientPluginPageTransport &&
      identical(client, other.client) &&
      _scope == other._scope &&
      entry.path == other.entry.path &&
      entry.revision == other.entry.revision;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(client), _scope, entry.path, entry.revision);

  String get _base =>
      '/ui/pages/${Uri.encodeComponent(entry.installationId)}/'
      '${Uri.encodeComponent(entry.pageId)}';

  @override
  Future<PluginPageDocument> loadPage() async => PluginPageDocument.fromJson(
    await client.request(_base, query: _negotiation),
  );

  @override
  Future<PluginQueryResult> runQuery(String queryId, Json input) async {
    final response = await client.request(
      '$_base/queries/${Uri.encodeComponent(queryId)}',
      method: 'POST',
      query: _negotiation,
      body: {'input': input},
    );
    return PluginQueryResult(
      data: response['data'],
      revision: label(response['revision'], ''),
    );
  }

  @override
  Future<PluginMutationResult> runAction(
    String actionId,
    Json input, {
    String? revision,
  }) async {
    final response = await client.request(
      '$_base/actions/${Uri.encodeComponent(actionId)}',
      method: 'POST',
      query: _negotiation,
      body: {
        'input': input,
        if (revision != null && revision.isNotEmpty) 'revision': revision,
      },
    );
    return PluginMutationResult(
      data: response['data'],
      revision: label(response['revision'], ''),
      invalidatedResources: response['invalidatedResources'] is List
          ? (response['invalidatedResources'] as List)
                .whereType<String>()
                .toList()
          : const [],
    );
  }
}

/// Restricted typed binding grammar: one level of source + dot path, never an
/// executable expression.
@immutable
class UiBinding {
  const UiBinding({required this.source, required this.path, this.resource});

  final String source;
  final String path;
  final String? resource;

  static UiBinding? tryParse(Object? value) {
    if (value is! Map) return null;
    final source = value['source'];
    final path = value['path'];
    if (source is! String ||
        !const {'resource', 'selection', 'form', 'item'}.contains(source) ||
        path is! String) {
      return null;
    }
    return UiBinding(
      source: source,
      path: path,
      resource: value['resource'] is String
          ? value['resource'] as String
          : null,
    );
  }
}

Object? walkPath(Object? value, String path) {
  if (path.isEmpty) return value;
  var current = value;
  for (final segment in path.split('.')) {
    if (segment.isEmpty) continue;
    if (current is Map) {
      current = current[segment];
    } else if (current is List) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= current.length) return null;
      current = current[index];
    } else {
      return null;
    }
  }
  return current;
}

Object? resolveBinding(
  Object? value, {
  required Map<String, PluginResourceState> resources,
  required Map<String, Object?> selectionByResource,
  required Object? globalSelection,
  required Map<String, Map<String, dynamic>> formValues,
  required String? formId,
  required Object? item,
  String? currentResource,
}) {
  if (value is String || value is num || value is bool || value == null) {
    return value;
  }
  final binding = UiBinding.tryParse(value);
  if (binding == null) return null;
  final resourceId = binding.resource ?? currentResource;
  final root = switch (binding.source) {
    'resource' => resources[resourceId]?.data,
    'selection' =>
      resourceId == null ? globalSelection : selectionByResource[resourceId],
    'form' => formValues[formId]?[binding.path.split('.').first],
    'item' => item,
    _ => null,
  };
  if (binding.source == 'form') {
    // Form values may themselves be nested maps when a single field holds a
    // JSON object. Walk the remaining path after the field name.
    final field = binding.path.split('.').first;
    final rest = binding.path.substring(field.length);
    if (rest.isEmpty) return formValues[formId]?[field];
    return walkPath(formValues[formId]?[field], rest.replaceFirst('.', ''));
  }
  return walkPath(root, binding.path);
}

class _RenderContext {
  const _RenderContext({this.formId, this.item, this.collectionResource});

  final String? formId;
  final Object? item;
  final String? collectionResource;

  _RenderContext withForm(String id) => _RenderContext(
    formId: id,
    item: item,
    collectionResource: collectionResource,
  );

  _RenderContext withItem(Object? value, String? resource) => _RenderContext(
    formId: formId,
    item: value,
    collectionResource: resource ?? collectionResource,
  );
}

class PluginPageScreen extends StatelessWidget {
  const PluginPageScreen({
    required this.client,
    required this.entry,
    required this.allowedDestinations,
    required this.onNavigate,
    required this.isCurrent,
    this.readOnly = false,
    super.key,
  });

  final GreenhouseClient client;
  final PluginPageEntry entry;
  final Map<String, String> allowedDestinations;
  final ValueChanged<String> onNavigate;
  final bool Function() isCurrent;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => PluginPageBody(
    transport: ClientPluginPageTransport(client: client, entry: entry),
    entry: entry,
    allowedDestinations: allowedDestinations,
    onNavigate: onNavigate,
    isCurrent: isCurrent,
    roleReadOnly: readOnly,
    allowAdminActions: client.permissions.canManageSharedFinances,
  );
}

/// Generic host-owned renderer for UI versions 1 and 2.
class PluginPageBody extends StatefulWidget {
  const PluginPageBody({
    required this.transport,
    required this.entry,
    required this.allowedDestinations,
    required this.onNavigate,
    this.isCurrent = _alwaysCurrent,
    this.roleReadOnly = false,
    this.allowAdminActions = false,
    this.privacyMasked = false,
    super.key,
  });

  final PluginPageTransport transport;
  final PluginPageEntry entry;
  final Map<String, String> allowedDestinations;
  final ValueChanged<String> onNavigate;
  final bool Function() isCurrent;
  final bool roleReadOnly;
  final bool allowAdminActions;
  final bool privacyMasked;

  static bool _alwaysCurrent() => true;

  @override
  State<PluginPageBody> createState() => _PluginPageBodyState();
}

class _PluginPageBodyState extends State<PluginPageBody> {
  PluginPageDocument? document;
  Object? error;
  bool loading = true;
  int _loadGeneration = 0;
  final Map<String, PluginResourceState> resources = {};
  final Map<String, Object?> selectionByResource = {};
  Object? globalSelection;
  final Map<String, Map<String, dynamic>> formValues = {};
  final Map<String, String> formScopes = {};
  final Map<String, TextEditingController> controllers = {};
  final Map<String, FocusNode> searchFocus = {};
  final Map<String, TextEditingController> searchControllers = {};
  final Map<String, String> fieldErrors = {};
  final Map<String, int> _fieldEpochs = {};
  final Set<String> pendingActions = {};
  final Map<String, Json> lastQueryInputs = {};
  final Map<String, int> queryGenerations = {};
  final Map<String, bool> querying = {};
  final Map<String, bool> appending = {};
  final Map<String, VoidCallback> _sheetRefresh = {};
  final Set<Route<dynamic>> _overlays = {};
  final Map<String, Route<void>> _dialogs = {};
  bool _dialogsScheduled = false;
  int _interactionGeneration = 0;
  bool _sheetRefreshScheduled = false;
  bool _active = true;
  final Map<String, GlobalKey> _cardKeys = {};
  ScrollPosition? _scrollPosition;
  String? _focusedCardId;
  bool _focusScheduled = false;

  bool get readOnly => widget.roleReadOnly || document?.readOnly == true;
  bool get mutationPending => pendingActions.isNotEmpty;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant PluginPageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.entry.path != widget.entry.path ||
        oldWidget.entry.revision != widget.entry.revision ||
        oldWidget.transport != widget.transport ||
        oldWidget.roleReadOnly != widget.roleReadOnly ||
        oldWidget.allowAdminActions != widget.allowAdminActions ||
        oldWidget.privacyMasked != widget.privacyMasked ||
        oldWidget.entry.available != widget.entry.available;
    if (changed || !widget.isCurrent()) {
      _clearPage();
      if (_stillCurrent()) unawaited(_load());
    }
  }

  // Modal routes outlive their originating widget. Track only this page's
  // routes so leaving the page never removes an unrelated host route.
  void _closeOverlays() {
    final routes = _overlays.toList();
    _overlays.clear();
    _dialogs.clear();
    _sheetRefresh.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final route in routes) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
    });
  }

  Future<T?> _pushOverlay<T>(Route<T> route) {
    if (!_stillCurrent()) return Future<T?>.value();
    _overlays.add(route);
    return Navigator.of(context).push(route).whenComplete(() {
      _overlays.remove(route);
    });
  }

  void _clearPage() {
    ++_interactionGeneration;
    ++_loadGeneration;
    queryGenerations.clear();
    querying.clear();
    appending.clear();
    _cardKeys.clear();
    _focusedCardId = null;
    _scrollPosition?.removeListener(_scheduleFocus);
    _scrollPosition = null;
    _closeOverlays();
    document = null;
    resources.clear();
    selectionByResource.clear();
    globalSelection = null;
    formScopes.clear();
    formValues.clear();
    fieldErrors.clear();
    _fieldEpochs.clear();
    lastQueryInputs.clear();
    pendingActions.clear();
    _disposeFormControllers('');
    for (final controller in searchControllers.values) {
      controller.clear();
    }
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (_sheetRefresh.isEmpty || _sheetRefreshScheduled) return;
    _sheetRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sheetRefreshScheduled = false;
      if (!mounted) return;
      for (final refresh in _sheetRefresh.values.toList()) {
        refresh();
      }
    });
  }

  @override
  void deactivate() {
    _active = false;
    _closeOverlays();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void dispose() {
    ++_interactionGeneration;
    _closeOverlays();
    _scrollPosition?.removeListener(_scheduleFocus);
    for (final controller in controllers.values) {
      controller.dispose();
    }
    for (final controller in searchControllers.values) {
      controller.dispose();
    }
    for (final focus in searchFocus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  bool _stillCurrent() =>
      mounted &&
      _active &&
      widget.isCurrent() &&
      widget.entry.available &&
      !widget.privacyMasked;

  Future<void> _load({bool preserveSelection = false}) async {
    if (!_stillCurrent()) return;
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final page = await widget.transport.loadPage();
      if (!_stillCurrent() || generation != _loadGeneration) return;
      setState(() {
        document = page;
        resources
          ..clear()
          ..addAll(page.resources);
        loading = false;
        _reconcileSelection(preserveSelection);
      });
    } catch (caught) {
      if (!_stillCurrent() || generation != _loadGeneration) return;
      setState(() {
        loading = false;
        error = caught;
        resources.clear();
      });
    }
  }

  Future<void> _reload() => _load(preserveSelection: true);

  void _reconcileSelection(bool preserve) {
    if (!preserve) {
      selectionByResource.clear();
      globalSelection = null;
      return;
    }
    for (final entry in selectionByResource.entries.toList()) {
      final replaced = _findSelected(entry.key, entry.value);
      if (replaced == null) {
        selectionByResource.remove(entry.key);
        if (identical(globalSelection, entry.value)) globalSelection = null;
      } else {
        selectionByResource[entry.key] = replaced;
        if (identical(globalSelection, entry.value)) globalSelection = replaced;
      }
    }
  }

  Object? _findSelected(String resourceId, Object? selected) {
    final items = pluginItems(resources[resourceId]?.data);
    if (selected == null) return null;
    if (selected is! Map) return items.contains(selected) ? selected : null;
    final id = selected['id'];
    if (id == null) return null;
    return items.where((item) => item['id'] == id).firstOrNull;
  }

  Object? _resolve(Object? value, _RenderContext context, {String? resource}) =>
      resolveBinding(
        value,
        resources: resources,
        selectionByResource: selectionByResource,
        globalSelection: globalSelection,
        formValues: formValues,
        formId: context.formId,
        item: context.item,
        currentResource: resource ?? context.collectionResource,
      );

  String _text(Object? value, _RenderContext context, {String? resource}) {
    final resolved = _resolve(value, context, resource: resource);
    return resolved == null ? '' : '$resolved';
  }

  void _select(String? resourceId, Object? item) {
    if (!_stillCurrent()) return;
    setState(() {
      globalSelection = item;
      if (resourceId != null) selectionByResource[resourceId] = item;
    });
    _syncBoundQueries(resourceId);
  }

  Json? _boundInput(Json component) {
    final declared = object(component['input']);
    if (declared.isEmpty) return null;
    final input = <String, dynamic>{'limit': 100, 'offset': 0};
    for (final entry in declared.entries) {
      final value = _resolve(entry.value, const _RenderContext());
      if (value == null || (value is String && value.trim().isEmpty)) {
        return null;
      }
      input[entry.key] = value;
    }
    return input;
  }

  void _syncBoundQueries(String? changedResource) {
    for (final component in _spec.components) {
      if (!const {'collection', 'dialog'}.contains(component['type'])) continue;
      final resourceId = label(component['resource'], '');
      if (resourceId.isEmpty || resourceId == changedResource) continue;
      final input = _boundInput(component);
      if (input == null) {
        if (lastQueryInputs[resourceId] != null ||
            querying[resourceId] == true) {
          setState(() {
            resources.remove(resourceId);
            selectionByResource.remove(resourceId);
            lastQueryInputs.remove(resourceId);
            queryGenerations[resourceId] =
                (queryGenerations[resourceId] ?? 0) + 1;
            querying.remove(resourceId);
            appending.remove(resourceId);
          });
        }
        continue;
      }
      if (jsonEncode(input) != jsonEncode(lastQueryInputs[resourceId])) {
        unawaited(_queryResource(resourceId, input));
      }
    }
  }

  Future<void> _queryResource(
    String resourceId,
    Json input, {
    bool append = false,
  }) async {
    if (!_stillCurrent()) return;
    final interaction = _interactionGeneration;
    final generation = (queryGenerations[resourceId] ?? 0) + 1;
    queryGenerations[resourceId] = generation;
    setState(() {
      if (!append &&
          jsonEncode(input) != jsonEncode(lastQueryInputs[resourceId])) {
        resources.remove(resourceId);
        selectionByResource.remove(resourceId);
      }
      querying[resourceId] = true;
      lastQueryInputs[resourceId] = Map<String, dynamic>.from(input);
      appending[resourceId] = append;
    });
    try {
      final result = await widget.transport.runQuery(resourceId, input);
      if (!_stillCurrent() ||
          interaction != _interactionGeneration ||
          queryGenerations[resourceId] != generation) {
        return;
      }
      setState(() {
        final previous = resources[resourceId]?.data;
        final data = append
            ? <String, dynamic>{
                ...object(previous),
                ...object(result.data),
                'items': [
                  ...pluginItems(previous),
                  ...pluginItems(result.data),
                ],
              }
            : result.data;
        resources[resourceId] = PluginResourceState(
          data: data,
          revision: result.revision,
        );
        lastQueryInputs[resourceId] = input;
        _reconcileSelection(true);
      });
    } catch (caught) {
      if (_stillCurrent() &&
          mounted &&
          interaction == _interactionGeneration &&
          queryGenerations[resourceId] == generation) {
        showMessage(context, errorMessage(caught));
      }
    } finally {
      if (mounted &&
          interaction == _interactionGeneration &&
          queryGenerations[resourceId] == generation) {
        setState(() {
          querying[resourceId] = false;
          appending[resourceId] = false;
        });
      }
    }
  }

  Future<void> _loadMore(Json component) async {
    final resourceId = label(component['resource'], '');
    if (resourceId.isEmpty || appending[resourceId] == true) return;
    final input = {...?lastQueryInputs[resourceId]};
    input['offset'] = pluginItems(resources[resourceId]?.data).length;
    await _queryResource(resourceId, input, append: true);
  }

  Future<void> _runSearch(Json component, String value) async {
    final resourceId = label(component['resource'], '');
    if (resourceId.isEmpty) return;
    setState(() {
      selectionByResource.remove(resourceId);
      for (final dependent in _dependentsOf(resourceId)) {
        selectionByResource.remove(dependent);
        resources.remove(dependent);
        queryGenerations[dependent] = (queryGenerations[dependent] ?? 0) + 1;
        querying.remove(dependent);
        appending.remove(dependent);
        lastQueryInputs.remove(dependent);
      }
    });
    await _queryResource(resourceId, {
      'search': value.trim(),
      'limit': 100,
      'offset': 0,
    });
  }

  void _clearSearch(Json component) {
    final id = label(component['id'], '');
    final resourceId = label(component['resource'], '');
    searchControllers[id]?.clear();
    searchFocus[id]?.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      selectionByResource.remove(resourceId);
      for (final dependent in _dependentsOf(resourceId)) {
        selectionByResource.remove(dependent);
        resources.remove(dependent);
        queryGenerations[dependent] = (queryGenerations[dependent] ?? 0) + 1;
        querying.remove(dependent);
        appending.remove(dependent);
        lastQueryInputs.remove(dependent);
      }
    });
    if (resourceId.isNotEmpty) {
      unawaited(
        _queryResource(resourceId, {'search': '', 'limit': 100, 'offset': 0}),
      );
    }
  }

  Set<String> _dependentsOf(String resourceId) {
    final dependents = <String>{};
    for (final component in _spec.components) {
      if (!const {'collection', 'dialog'}.contains(component['type'])) continue;
      final resource = label(component['resource'], '');
      final declared = object(component['input']);
      if (resource.isEmpty || declared.isEmpty) continue;
      for (final value in declared.values) {
        final binding = UiBinding.tryParse(value);
        if (binding?.source == 'selection' && binding?.resource == resourceId) {
          dependents.add(resource);
        }
      }
    }
    return dependents;
  }

  Future<void> _refreshInvalidated(List<String> ids) async {
    for (final id in ids) {
      final resource = _spec.resource(id);
      if (resource == null) continue;
      final input = lastQueryInputs[id] ?? object(resource['initialInput']);
      await _queryResource(id, input);
    }
  }

  String _formScope(Json form, _RenderContext context) {
    final resourceId = label(form['resource'], '');
    final selected = resourceId.isEmpty
        ? null
        : selectionByResource[resourceId];
    if (selected is Map && selected['id'] != null) return '${selected['id']}';
    if (context.item is Map && (context.item as Map)['id'] != null) {
      return '${(context.item as Map)['id']}';
    }
    return 'new';
  }

  void _resetForm(String formId) {
    formScopes.remove(formId);
    formValues.remove(formId);
    fieldErrors.removeWhere((key, _) => key.startsWith('$formId.'));
    _disposeFormControllers(formId);
  }

  String _errorKey(String formId, String path) => '$formId.$path';

  bool _validateForm(Json form, String formId) {
    final values = formValues[formId] ?? {};
    final errors = <String, String>{};
    for (final field in objects(form['fields'])) {
      final name = label(field['name'], '');
      if (name.isEmpty) continue;
      if (field['type'] == 'repeater') {
        final rows = values[name] is List ? values[name] as List : const [];
        for (var index = 0; index < rows.length; index++) {
          final row = object(rows[index]);
          for (final child in objects(field['fields'])) {
            final childName = label(child['name'], '');
            if (childName.isEmpty || child['required'] != true) continue;
            final value = row[childName];
            if (value == null || (value is String && value.trim().isEmpty)) {
              errors[_errorKey(formId, '$name.$index.$childName')] = 'Required';
            }
          }
        }
        continue;
      }
      if (field['required'] != true) continue;
      final value = values[name];
      if (value == null || (value is String && value.trim().isEmpty)) {
        errors[_errorKey(formId, name)] = 'Required';
      }
    }
    setState(() {
      fieldErrors.removeWhere((key, _) => key.startsWith('$formId.'));
      fieldErrors.addAll(errors);
    });
    return errors.isEmpty;
  }

  Future<void> _submitForm(
    Json form,
    Json action,
    _RenderContext context,
  ) async {
    final formId = label(form['id'], '');
    if (!_validateForm(form, formId)) return;
    final draft = <String, dynamic>{};
    for (final field in objects(form['fields'])) {
      final name = label(field['name'], '');
      if (name.isNotEmpty) draft[name] = formValues[formId]?[name];
    }
    await _runAction(
      action,
      form,
      context.withForm(formId),
      extraInput: draft,
      formId: formId,
    );
  }

  Future<void> _runAction(
    Json action,
    Json component,
    _RenderContext renderContext, {
    Json extraInput = const {},
    String? formId,
  }) async {
    final actionId = label(action['id'], '');
    if (actionId.isEmpty || mutationPending) return;
    if (readOnly || !_stillCurrent()) return;
    final interaction = _interactionGeneration;
    if (label(action['access'], 'member') == 'admin' &&
        !widget.allowAdminActions) {
      return;
    }
    final input = <String, dynamic>{};
    for (final entry in object(component['input']).entries) {
      input[entry.key] = _resolve(entry.value, renderContext);
    }
    input.addAll(extraInput);
    final resourceId = label(component['resource'], '');
    final revision = resourceId.isEmpty
        ? null
        : resources[resourceId]?.revision;
    final declaredConfirmation = action['confirmation'];
    var confirmation = declaredConfirmation is String
        ? declaredConfirmation
        : '';
    if (declaredConfirmation is Map) {
      final condition = object(declaredConfirmation);
      final key = label(condition['input'], '');
      if (key.isEmpty ||
          UiBinding.tryParse(condition['from']) == null ||
          condition['message'] is! String) {
        return;
      }
      final when = condition['when'] == null
          ? true
          : _resolve(condition['when'], renderContext);
      final truthy = when != null && when != false && when != '' && when != 0;
      if (truthy &&
          jsonEncode(input[key]) !=
              jsonEncode(_resolve(condition['from'], renderContext))) {
        confirmation = condition['message'] as String;
      }
    } else if (declaredConfirmation != null &&
        declaredConfirmation is! String) {
      return;
    }
    if (confirmation.isNotEmpty) {
      final accepted = await _pushOverlay<bool>(
        DialogRoute<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(
              label(component['label'], label(action['id'], 'Continue')),
            ),
            content: Text(confirmation),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      );
      if (accepted != true ||
          !_stillCurrent() ||
          interaction != _interactionGeneration ||
          readOnly ||
          mutationPending) {
        return;
      }
    }
    setState(() => pendingActions.add(actionId));
    try {
      final result = await widget.transport.runAction(
        actionId,
        input,
        revision: revision,
      );
      if (!_stillCurrent() || interaction != _interactionGeneration) return;
      if (resourceId.isNotEmpty && result.revision.isNotEmpty) {
        final current = resources[resourceId];
        if (current != null) {
          resources[resourceId] = PluginResourceState(
            data: current.data,
            revision: result.revision,
          );
        }
      }
      setState(() {
        if (formId == null) {
          fieldErrors.clear();
        } else {
          fieldErrors.removeWhere((key, _) => key.startsWith('$formId.'));
        }
      });
      await _refreshInvalidated(result.invalidatedResources);
      if (!_stillCurrent()) return;
      if (formId != null) _resetForm(formId);
      for (final refresh in _sheetRefresh.values.toList()) {
        refresh();
      }
      if (!mounted) return;
      showMessage(context, 'Saved.');
    } on GreenhouseException catch (caught) {
      if (!_stillCurrent() || interaction != _interactionGeneration) return;
      final details = caught.details;
      final fieldErrorsValue = details?['fieldErrors'];
      final mapped = <String, String>{};
      if (fieldErrorsValue is Map) {
        for (final entry in fieldErrorsValue.entries) {
          final fieldName = '${entry.key}';
          final value = entry.value is String ? entry.value as String : '';
          var matched = false;
          for (final form in _forms) {
            final id = label(form['id'], '');
            final fields = objects(form['fields']);
            if (fields.any((field) {
              final name = label(field['name'], '');
              return fieldName == name || fieldName.startsWith('$name.');
            })) {
              mapped[_errorKey(id, fieldName)] = value;
              matched = true;
            }
          }
          if (!matched) mapped[_errorKey(actionId, fieldName)] = value;
        }
      }
      setState(() => fieldErrors.addAll(mapped));
      for (final refresh in _sheetRefresh.values.toList()) {
        refresh();
      }
      if (!mounted) return;
      showMessage(
        context,
        mapped.isEmpty ? caught.message : 'Check the highlighted fields.',
      );
    } catch (caught) {
      if (_stillCurrent() && mounted) {
        showMessage(context, errorMessage(caught));
      }
    } finally {
      if (mounted) setState(() => pendingActions.remove(actionId));
    }
  }

  PluginPageSpec get _spec => PluginPageSpec.fromJson(document?.ui ?? const {});

  List<Json> get _forms => _spec.components
      .where((component) => component['type'] == 'form')
      .toList();

  @override
  Widget build(BuildContext context) {
    if (widget.privacyMasked) {
      return const FinanceList(
        children: [
          Panel(
            child: Text('Plugin content is hidden while privacy mode is on.'),
          ),
        ],
      );
    }
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return FinanceList(
        onRefresh: _reload,
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(errorMessage(error!)),
                TextButton(onPressed: _reload, child: const Text('Try again')),
              ],
            ),
          ),
        ],
      );
    }
    final page = document;
    if (page == null) {
      return const FinanceList(
        children: [Panel(child: Text('This page is unavailable.'))],
      );
    }
    final spec = _spec;
    final supportedTypes = pluginComponentCapabilities
        .map((capability) => capability.split('.').first)
        .toSet();
    final unsupported =
        spec.version != 2 ||
        spec.requiredCapabilities.any(
          (capability) => !pluginComponentCapabilities.contains(capability),
        ) ||
        spec.components.any(
          (component) => !supportedTypes.contains(component['type']),
        );
    final header = <Widget>[
      if (page.title.isNotEmpty)
        Text(page.title, style: Theme.of(context).textTheme.headlineMedium),
      if (widget.entry.description case final description?
          when description.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(description),
      ],
      const SizedBox(height: 8),
    ];
    if (spec.version == 0) {
      return FinanceList(
        onRefresh: _reload,
        children: [
          ...header,
          const Panel(child: Text('This page declaration is not supported.')),
        ],
      );
    }
    if (spec.version == 1) {
      return FinanceList(
        onRefresh: _reload,
        children: [...header, ..._versionOne(context, page)],
      );
    }
    if (unsupported) {
      return FinanceList(
        onRefresh: _reload,
        children: [
          ...header,
          const Panel(
            child: Text(
              'This page needs a newer version of GreenHouse. Update the app to open it.',
            ),
          ),
        ],
      );
    }
    final byId = {for (final row in spec.components) label(row['id'], ''): row};
    final malformed =
        spec.roots.isEmpty ||
        spec.roots.any((id) => !byId.containsKey(id)) ||
        spec.components.length > 120 ||
        !spec.hasValidTree;
    if (malformed) {
      return FinanceList(
        onRefresh: _reload,
        children: [
          ...header,
          const Panel(child: Text('This page declaration is not supported.')),
        ],
      );
    }
    _scheduleDialogs(byId);
    return FinanceList(
      onRefresh: _reload,
      children: [
        ...header,
        if (readOnly)
          const Panel(
            child: Text(
              'This page is read-only for your household role or the plugin.',
            ),
          ),
        for (final id in spec.roots)
          ..._component(byId, id, const _RenderContext(), const <String>{}, 0),
      ],
    );
  }

  List<Widget> _component(
    Map<String, Json> byId,
    String id,
    _RenderContext context,
    Set<String> ancestors,
    int depth,
  ) {
    final component = byId[id];
    if (component == null || depth >= 8 || ancestors.contains(id)) {
      return const [];
    }
    if (component['visibleWhen'] != null) {
      final visible = _resolve(component['visibleWhen'], context);
      if (visible == null ||
          visible == false ||
          (visible is String && visible.isEmpty)) {
        return const [];
      }
    }
    final nextAncestors = {...ancestors, id};
    List<Widget> children() => [
      for (final child
          in component['children'] is List
              ? (component['children'] as List).whereType<String>()
              : const <String>[])
        ..._component(byId, child, context, nextAncestors, depth + 1),
    ];
    final type = label(component['type'], '');
    // Privacy masks the entire page, including owned overlays, before rendering.
    Widget sensitive(Widget child) => child;
    switch (type) {
      case 'section':
        final title = _text(component['title'], context);
        return [if (title.isNotEmpty) SectionTitle(title), ...children()];
      case 'text':
        final text = _text(component['text'] ?? component['title'], context);
        return [if (text.isNotEmpty) sensitive(Text(text))];
      case 'notice':
        final text = _text(component['text'] ?? component['title'], context);
        return [
          if (text.isNotEmpty)
            sensitive(
              _Notice(text: text, tone: label(component['tone'], 'info')),
            ),
        ];
      case 'image':
        final imageItem = _resolve(component['data'], context);
        if (imageItem is Map) return [sensitive(_itemHero(imageItem))];
        final source = _text(component['src'], context);
        final alt = _text(component['alt'], context);
        return [
          if (source.startsWith('https://'))
            sensitive(
              Semantics(
                image: true,
                label: alt.isEmpty ? 'Plugin image' : alt,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    source,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
        ];
      case 'facts':
        return [sensitive(_facts(component, context))];
      case 'collection':
        return [sensitive(_collection(byId, component, context))];
      case 'search':
        return [_search(component, context)];
      case 'picker':
        return [_picker(component, context)];
      case 'dialog':
        return const [];
      case 'disclosure':
        return [
          ExpansionTile(
            key: ValueKey('disclosure-$id'),
            title: Text(
              _text(component['title'] ?? component['label'], context),
            ),
            children: children(),
          ),
        ];
      case 'form':
        return [_form(byId, component, context, nextAncestors, depth)];
      case 'button':
        return [_button(component, context)];
      case 'collection-detail':
        final childIds = component['children'] is List
            ? (component['children'] as List).whereType<String>().toList()
            : const <String>[];
        final primary = childIds
            .where((id) => byId[id]?['type'] == 'collection')
            .firstOrNull;
        if (primary != null &&
            byId[primary]?['presentation'] == 'overlapping-cards') {
          return [
            for (final child
                in (component['emptyChildren'] as List? ?? const [])
                    .whereType<String>())
              ..._component(byId, child, context, nextAncestors, depth + 1),
            ..._component(byId, primary, context, nextAncestors, depth + 1),
          ];
        }
        if (primary != null &&
            component['emptyChildren'] is List &&
            selectionByResource[label(byId[primary]?['resource'], '')] ==
                null) {
          return [
            ..._component(byId, primary, context, nextAncestors, depth + 1),
            for (final child
                in (component['emptyChildren'] as List).whereType<String>())
              ..._component(byId, child, context, nextAncestors, depth + 1),
          ];
        }
        return [sensitive(_detail(component, context, children))];
      case 'link':
        return [_link(component, context)];
      default:
        return const [];
    }
  }

  Widget _facts(Json component, _RenderContext context) {
    final data = _resolve(component['data'], context);
    final rows = <(String, String)>[];
    if (data is Map) {
      for (final entry in data.entries) {
        rows.add((_humanize(entry.key), _display(entry.value)));
      }
    } else if (data is List) {
      for (final item in data) {
        final row = object(item);
        final name = label(row['label'], label(row['name'], ''));
        rows.add((name, _display(row['value'] ?? row['text'] ?? item)));
      }
    }
    final title = _text(component['title'], context);
    if (title.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title),
          if (rows.isEmpty)
            const Text('No rewards or benefits are listed.')
          else
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.$1,
                        style: Theme.of(this.context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(this.context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(row.$2),
                    ],
                  ),
                ),
              ),
        ],
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const Divider(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    rows[index].$1,
                    style: Theme.of(this.context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    rows[index].$2,
                    textAlign: TextAlign.end,
                    style: Theme.of(this.context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _collection(
    Map<String, Json> byId,
    Json component,
    _RenderContext context,
  ) {
    final resourceId = label(component['resource'], '');
    final data = _resolve(component['data'], context);
    final items = pluginItems(data);
    final empty = _text(component['emptyText'], context);
    final title = _text(component['title'], context);
    final loading = querying[resourceId] == true && items.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) SectionTitle(title),
        if (loading)
          const Panel(child: CircularProgressIndicator())
        else if (items.isEmpty)
          Panel(child: Text(empty.isNotEmpty ? empty : 'Nothing here yet.'))
        else if (component['presentation'] == 'overlapping-cards')
          _overlapping(byId, component, items, context, resourceId)
        else
          for (final item in items) ...[
            _collectionTile(byId, component, item, context, resourceId),
            const SizedBox(height: 9),
          ],
        if (pluginHasMore(resources[resourceId]?.data ?? data)) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: appending[resourceId] == true
                  ? null
                  : () => _loadMore(component),
              child: Text(
                appending[resourceId] == true ? 'Loading…' : 'Load more',
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _collectionTile(
    Map<String, Json> byId,
    Json component,
    Object? item,
    _RenderContext context,
    String resourceId,
  ) {
    final selected = _isSelected(resourceId, item);
    final inlineChildren = component['children'] is List
        ? (component['children'] as List).whereType<String>().where(
            (child) => byId[child]?['type'] != 'collection-detail',
          )
        : const <String>[];
    return Panel(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _select(resourceId.isEmpty ? null : resourceId, item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _itemPreview(item)),
                if (selected) const Icon(Icons.check_circle_outline, size: 20),
              ],
            ),
            if (inlineChildren.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final child in inlineChildren)
                ..._component(
                  byId,
                  child,
                  context.withItem(item, resourceId),
                  const <String>{},
                  0,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _overlapping(
    Map<String, Json> byId,
    Json component,
    List<Object?> items,
    _RenderContext context,
    String resourceId,
  ) {
    final textScale = MediaQuery.textScalerOf(this.context)
        .scale(1)
        .clamp(1.0, 2.0);
    final cardHeight = 168 * textScale;
    final slotHeight = cardHeight * .35;
    final reducedMotion = MediaQuery.disableAnimationsOf(this.context);
    if (!reducedMotion && _focusedCardId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleFocus());
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        if (!reducedMotion) _scheduleFocus();
        return false;
      },
      child: Builder(
        builder: (scrollContext) {
          final position = Scrollable.maybeOf(scrollContext)?.position;
          if (!identical(position, _scrollPosition)) {
            _scrollPosition?.removeListener(_scheduleFocus);
            _scrollPosition = position;
            if (!reducedMotion) position?.addListener(_scheduleFocus);
          }
          return SizedBox(
            height: cardHeight + (items.length - 1) * slotHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var index = 0; index < items.length; index++)
                  Positioned(
                    top: index * slotHeight,
                    left: 0,
                    right: 0,
                    height: cardHeight,
                    key: _cardKeys.putIfAbsent(
                      _cardIdentity(resourceId, items[index]),
                      GlobalKey.new,
                    ),
                    child: _walletCard(
                      byId,
                      component,
                      items[index],
                      index,
                      cardHeight,
                      resourceId,
                      selected: _isSelected(resourceId, items[index]),
                      focused:
                          _focusedCardId ==
                          _cardIdentity(resourceId, items[index]),
                      reducedMotion: reducedMotion,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _walletCard(
    Map<String, Json> byId,
    Json component,
    Object? item,
    int index,
    double height,
    String resourceId, {
    required bool selected,
    required bool focused,
    required bool reducedMotion,
  }) {
    final scale = focused && !reducedMotion ? 1.04 : 1.0;
    final lift = focused && !reducedMotion ? -15.0 : 0.0;
    final row = object(item);
    final image = label(row['imageUrl'], '');
    return AnimatedContainer(
      key: ValueKey('card-transform-${_cardIdentity(resourceId, item)}'),
      duration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      transform: Matrix4.translationValues(0, lift, 0)
        ..scaleByDouble(scale, scale, 1, 1),
      transformAlignment: Alignment.center,
      child: Semantics(
        button: true,
        selected: selected,
        label:
            '${_itemTitle(item)}, card ${index + 1} of ${itemCountFor(resourceId)}',
        child: GestureDetector(
          onTap: () {
            _select(resourceId.isEmpty ? null : resourceId, item);
            _openDetail(byId, component, item, resourceId);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _itemTone(item),
                    _itemTone(item).withValues(alpha: .65),
                  ],
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (image.startsWith('https://'))
                    Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: .3),
                          Colors.transparent,
                          Colors.black.withValues(alpha: .65),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    left: 16,
                    right: 16,
                    child: Text(
                      _itemTitle(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 14,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (label(row['caption'], '').isNotEmpty)
                          Text(
                            label(row['caption'], ''),
                            style: const TextStyle(color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _toneColor(String tone) => switch (tone) {
    'forest' => const Color(0xff296b4c),
    'ocean' => const Color(0xff286c91),
    'plum' => const Color(0xff79568c),
    'gold' => const Color(0xff987021),
    _ => Theme.of(context).colorScheme.primary,
  };

  Color _itemTone(Object? item) =>
      _toneColor(label(object(item)['tone'], 'neutral'));

  List<Widget> _itemMetadata(Object? item, {bool compact = false}) {
    final row = object(item);
    final caption = label(row['caption'], '');
    final badges = objects(row['badges']);
    return [
      if (caption.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          caption,
          maxLines: compact ? 1 : null,
          overflow: compact ? TextOverflow.ellipsis : null,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      if (badges.isNotEmpty) ...[
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final badge in badges)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _toneColor(label(badge['tone'], 'neutral'))
                      .withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label(badge['label'], ''),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
          ],
        ),
      ],
    ];
  }

  Widget _itemPreview(Object? item) {
    final row = object(item);
    final image = label(row['imageUrl'], '');
    final issuer = label(row['issuerLogoUrl'], '');
    final fallback = label(row['fallbackLabel'], _itemTitle(item));
    Widget placeholder() => Container(
      color: _itemTone(item).withValues(alpha: .16),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(6),
      child: Text(
        fallback,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
    return Row(
      children: [
        if (image.isNotEmpty ||
            issuer.isNotEmpty ||
            row['fallbackLabel'] != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 76,
              height: 48,
              child: image.startsWith('https://')
                  ? Image.network(
                      image,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => placeholder(),
                    )
                  : issuer.startsWith('https://')
                  ? Image.network(
                      issuer,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => placeholder(),
                    )
                  : placeholder(),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _itemTitle(item),
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (_itemSubtitle(item).isNotEmpty)
                Text(
                  _itemSubtitle(item),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ..._itemMetadata(item),
            ],
          ),
        ),
      ],
    );
  }

  int itemCountFor(String resourceId) =>
      pluginItems(resources[resourceId]?.data).length;

  String _cardIdentity(String resourceId, Object? item) {
    if (item is Map && item['id'] != null) return '$resourceId:${item['id']}';
    return '$resourceId:${identityHashCode(item)}';
  }

  void _scheduleFocus() {
    if (_focusScheduled || !mounted) return;
    _focusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusScheduled = false;
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) return;
      final center = MediaQuery.sizeOf(context).height / 2;
      String? best;
      var bestDistance = double.infinity;
      for (final entry in _cardKeys.entries) {
        final box = entry.value.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.attached) continue;
        final position = box.localToGlobal(Offset.zero);
        final distance = (position.dy + box.size.height / 2 - center).abs();
        if (distance < bestDistance) {
          bestDistance = distance;
          best = entry.key;
        }
      }
      if (best != null && best != _focusedCardId) {
        setState(() => _focusedCardId = best);
      }
    });
  }

  bool _isSelected(String resourceId, Object? item) {
    final selected = resourceId.isEmpty
        ? globalSelection
        : selectionByResource[resourceId];
    if (selected is Map && item is Map) return selected['id'] == item['id'];
    return identical(selected, item);
  }

  void _openDetail(
    Map<String, Json> byId,
    Json collection,
    Object? item,
    String resourceId,
  ) {
    final collectionId = label(collection['id'], '');
    Json? layout;
    for (final candidate in byId.values) {
      if (candidate['type'] != 'collection-detail') continue;
      if (candidate['children'] is List &&
          (candidate['children'] as List).contains(collectionId)) {
        layout = candidate;
        break;
      }
    }
    if (layout == null) return;
    final detailIds = (layout['children'] as List)
        .whereType<String>()
        .where((id) => byId[id]?['type'] != 'collection')
        .toList();
    if (detailIds.isEmpty) return;
    bool hasItemArtwork(String id, int depth) {
      if (depth >= 8) return false;
      final component = byId[id];
      if (component == null) return false;
      final binding = UiBinding.tryParse(component['data']);
      if (component['type'] == 'image' &&
          binding?.path == '' &&
          (binding?.source == 'item' ||
              (binding?.source == 'selection' &&
                  (binding?.resource ?? resourceId) == resourceId))) {
        return true;
      }
      return (component['children'] as List? ?? const [])
          .whereType<String>()
          .any((child) => hasItemArtwork(child, depth + 1));
    }

    final suppliedPreview = detailIds.any((id) => hasItemArtwork(id, 0));
    if (!_stillCurrent()) return;
    final refreshTokens = <String>{};
    _pushOverlay<void>(
      ModalBottomSheetRoute<void>(
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: Navigator.of(context).context,
        ),
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            final token = '${identityHashCode(setSheetState)}';
            refreshTokens.add(token);
            _sheetRefresh[token] = () {
              if (context.mounted) setSheetState(() {});
            };
            if (!_stillCurrent()) return const SizedBox.shrink();
            final selected = resourceId.isEmpty
                ? globalSelection
                : selectionByResource[resourceId];
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) _sheetRefresh.remove(token);
            });
            return DraggableScrollableSheet(
              initialChildSize: .72,
              minChildSize: .45,
              maxChildSize: .94,
              expand: false,
              builder: (context, scrollController) => Column(
                children: [
                  _SheetHandle(onClose: () => Navigator.of(sheetContext).pop()),
                  Expanded(
                    child: ListView(
                      key: const ValueKey('plugin-detail-list'),
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                      children: [
                        if (!suppliedPreview) ...[
                          Text(
                            _itemTitle(selected ?? item),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 14),
                        ],
                        for (final id in detailIds)
                          ..._componentDetail(byId, id, item, resourceId),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ).whenComplete(() {
      for (final token in refreshTokens) {
        _sheetRefresh.remove(token);
      }
    });
  }

  List<Widget> _componentDetail(
    Map<String, Json> byId,
    String id,
    Object? item,
    String resourceId,
  ) {
    final component = byId[id];
    if (component == null) return const [];
    final context = _RenderContext(
      item: item,
      collectionResource: resourceId.isEmpty ? null : resourceId,
    );
    if (component['visibleWhen'] != null) {
      final visible = _resolve(component['visibleWhen'], context);
      if (visible == null || visible == false) return const [];
    }
    if (component['type'] == 'section') {
      return [
        for (final child
            in component['children'] is List
                ? (component['children'] as List).whereType<String>()
                : const <String>[])
          ..._componentDetail(byId, child, item, resourceId),
      ];
    }
    return _component(byId, id, context, const <String>{}, 0);
  }

  Widget _factsFromObject(Object? value) {
    final row = object(value);
    if (row.isEmpty) return Text(_display(value));
    return Panel(
      child: Column(
        children: [
          for (final entry in row.entries)
            if (entry.value is! Map && entry.value is! List)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(_humanize(entry.key))),
                    Flexible(
                      child: Text(
                        _display(entry.value),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  void _clearSelection(String resourceId) {
    if (!_stillCurrent()) return;
    setState(() {
      final removed = selectionByResource.remove(resourceId);
      if (identical(removed, globalSelection)) globalSelection = null;
      for (final dependent in _dependentsOf(resourceId)) {
        resources.remove(dependent);
        selectionByResource.remove(dependent);
        queryGenerations[dependent] = (queryGenerations[dependent] ?? 0) + 1;
        querying.remove(dependent);
        appending.remove(dependent);
        lastQueryInputs.remove(dependent);
      }
    });
    _syncBoundQueries(resourceId);
  }

  Widget _picker(Json component, _RenderContext renderContext) {
    final id = label(component['id'], '');
    final resourceId = label(component['resource'], '');
    final title = _text(
      component['label'] ?? component['title'] ?? component['text'],
      renderContext,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: OutlinedButton.icon(
        key: ValueKey('picker-$id'),
        icon: const Icon(Icons.search),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(title.isEmpty ? 'Choose an item' : title),
        ),
        onPressed: resourceId.isEmpty
            ? null
            : () async {
                if (!_stillCurrent()) return;
                _clearSelection(resourceId);
                final interaction = _interactionGeneration;
                final selected = await _pushOverlay<Object?>(
                  DialogRoute<Object?>(
                    context: context,
                    builder: (_) => _ResourcePickerDialog(
                      title: title,
                      transport: widget.transport,
                      resourceId: resourceId,
                      returnItem: true,
                      onResult: (result) {
                        if (!_stillCurrent() ||
                            interaction != _interactionGeneration) {
                          return;
                        }
                        setState(
                          () => resources[resourceId] = PluginResourceState(
                            data: result.data,
                            revision: result.revision,
                          ),
                        );
                      },
                      isCurrent: () =>
                          _stillCurrent() &&
                          interaction == _interactionGeneration,
                    ),
                  ),
                );
                if (!_stillCurrent() || interaction != _interactionGeneration) {
                  return;
                }
                FocusManager.instance.primaryFocus?.unfocus();
                if (selected is Map) _select(resourceId, object(selected));
              },
      ),
    );
  }

  bool _dialogVisible(Json component) {
    final value = _resolve(component['visibleWhen'], const _RenderContext());
    return value != null && value != false && value != '' && value != 0;
  }

  void _scheduleDialogs(Map<String, Json> byId) {
    if (_dialogsScheduled) return;
    _dialogsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dialogsScheduled = false;
      if (!_stillCurrent()) return;
      for (final component in byId.values.where(
        (row) => row['type'] == 'dialog',
      )) {
        final id = label(component['id'], '');
        final route = _dialogs[id];
        if (!_dialogVisible(component)) {
          if (route != null && route.isActive) {
            route.navigator?.removeRoute(route);
          }
        } else if (route == null) {
          _openDialog(byId, component);
        }
      }
    });
  }

  void _openDialog(Map<String, Json> byId, Json component) {
    if (!_stillCurrent()) return;
    final id = label(component['id'], '');
    final interaction = _interactionGeneration;
    final resourceId = label(component['resource'], '');
    final refreshToken = 'dialog-$id-$_interactionGeneration';
    late final ModalBottomSheetRoute<void> route;
    route = ModalBottomSheetRoute<void>(
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context).context,
      ),
      isScrollControlled: true,
      useSafeArea: true,
      modalBarrierColor: Colors.black54,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          _sheetRefresh[refreshToken] = () {
            if (sheetContext.mounted) setSheetState(() {});
          };
          if (!_stillCurrent() ||
              interaction != _interactionGeneration ||
              !_dialogVisible(component)) {
            return const SizedBox.shrink();
          }
          final item = _resolve(component['data'], const _RenderContext());
          final renderContext = _RenderContext(
            item: item,
            collectionResource: resourceId,
          );
          return DraggableScrollableSheet(
            initialChildSize: .76,
            minChildSize: .45,
            maxChildSize: .94,
            expand: false,
            builder: (_, controller) => Column(
              children: [
                _SheetHandle(onClose: () => Navigator.of(sheetContext).pop()),
                Expanded(
                  child: ListView(
                    key: ValueKey('dialog-content-$id'),
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                    children: [
                      Text(
                        _text(
                          component['title'] ?? component['label'],
                          renderContext,
                        ),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 14),
                      if (item == null && querying[resourceId] == true)
                        const Center(child: CircularProgressIndicator())
                      else if (item == null)
                        Text(label(component['emptyText'], 'Nothing here yet.'))
                      else
                        for (final child
                            in (component['children'] as List? ?? const [])
                                .whereType<String>())
                          ..._component(byId, child, renderContext, {id}, 1),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    _dialogs[id] = route;
    _pushOverlay<void>(route).whenComplete(() {
      if (identical(_dialogs[id], route)) _dialogs.remove(id);
      _sheetRefresh.remove(refreshToken);
      if (!_stillCurrent() || interaction != _interactionGeneration) return;
      final dismiss = label(component['dismissSelection'], '');
      if (dismiss.isNotEmpty) _clearSelection(dismiss);
    });
  }

  Widget _itemHero(Object? item) {
    final row = object(item);
    final image = label(row['imageUrl'], '');
    final issuer = label(row['issuerLogoUrl'], '');
    Widget fallback() => Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _itemTone(item).withValues(alpha: .45),
            _itemTone(item).withValues(alpha: .15),
          ],
        ),
      ),
      child: Center(
        child: issuer.startsWith('https://')
            ? SizedBox(
                height: 46,
                child: Image.network(
                  issuer,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      Text(label(row['fallbackLabel'], _itemTitle(item))),
                ),
              )
            : Text(
                label(row['fallbackLabel'], _itemTitle(item)),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: AspectRatio(
                  aspectRatio: 1.58,
                  child: image.startsWith('https://')
                      ? Image.network(
                          image,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => fallback(),
                        )
                      : fallback(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _itemTitle(item),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_itemSubtitle(item).isNotEmpty)
            Text(_itemSubtitle(item), textAlign: TextAlign.center),
          ..._itemMetadata(item),
        ],
      ),
    );
  }

  Widget _search(Json component, _RenderContext context) {
    final id = label(component['id'], '');
    final hint = _text(component['text'] ?? component['label'], context);
    final controller = searchControllers.putIfAbsent(
      id,
      TextEditingController.new,
    );
    final focus = searchFocus.putIfAbsent(id, FocusNode.new);
    return TextField(
      key: ValueKey('search-$id'),
      controller: controller,
      focusNode: focus,
      textInputAction: TextInputAction.search,
      onSubmitted: (value) {
        focus.unfocus();
        _runSearch(component, value);
      },
      onTapOutside: (_) => focus.unfocus(),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        suffixIcon: IconButton(
          tooltip: 'Clear search',
          onPressed: () => _clearSearch(component),
          icon: const Icon(Icons.close),
        ),
        labelText: hint.isEmpty ? 'Search' : hint,
      ),
    );
  }

  Widget _form(
    Map<String, Json> byId,
    Json component,
    _RenderContext context,
    Set<String> ancestors,
    int depth,
  ) {
    final formId = label(component['id'], '');
    final scope = _formScope(component, context);
    if (formScopes[formId] != scope) {
      _disposeFormControllers(formId);
      formScopes[formId] = scope;
      final values = <String, dynamic>{};
      formValues[formId] = values;
      fieldErrors.removeWhere((key, _) => key.startsWith('$formId.'));
      for (final field in objects(component['fields'])) {
        final name = label(field['name'], '');
        if (name.isEmpty || field['value'] == null) continue;
        final initial = _resolve(field['value'], context);
        if (initial is List) {
          values[name] = [
            for (final row in initial)
              if (row is Map) Map<String, dynamic>.from(row) else row,
          ];
        } else {
          values[name] = initial;
        }
      }
    }
    final existing = formValues.putIfAbsent(formId, () => <String, dynamic>{});
    final fields = objects(component['fields']);
    final action = _spec.action(label(component['action'], ''));
    final childHasAction =
        component['children'] is List &&
        (component['children'] as List).any(
          (child) => byId['$child']?['action'] == component['action'],
        );
    return Panel(
      key: ValueKey("form-$formId"),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_text(component['title'], context).isNotEmpty) ...[
            Text(
              _text(component['title'], context),
              style: Theme.of(this.context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
          ],
          for (final field in fields) ...[
            _field(formId, field, context, existing),
            const SizedBox(height: 10),
          ],
          if (component['children'] is List)
            for (final child
                in (component['children'] as List).whereType<String>())
              ..._component(
                byId,
                child,
                context.withForm(formId),
                ancestors,
                depth + 1,
              ),
          if (action != null && !childHasAction) ...[
            const SizedBox(height: 4),
            FilledButton(
              key: ValueKey('save-$formId'),
              onPressed:
                  readOnly ||
                      mutationPending ||
                      (label(action['access'], 'member') == 'admin' &&
                          !widget.allowAdminActions)
                  ? null
                  : () => _submitForm(component, action, context),
              child: Text(
                pendingActions.contains(label(action['id'], ''))
                    ? 'Saving…'
                    : 'Save',
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _disposeFormControllers(String formId) => _disposeControllersWhere(
    (key) => formId.isEmpty || key.startsWith('$formId.'),
  );

  void _disposeControllersWhere(bool Function(String key) matches) {
    final removed = <TextEditingController>[];
    controllers.removeWhere((key, controller) {
      if (!matches(key)) return false;
      removed.add(controller);
      return true;
    });
    if (removed.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in removed) {
        controller.dispose();
      }
    });
  }

  Widget _field(
    String formId,
    Json field,
    _RenderContext context,
    Map<String, dynamic> values,
  ) {
    final name = label(field['name'], '');
    if (name.isEmpty) return const SizedBox.shrink();
    if (label(field['type'], '') == 'repeater') {
      return _repeater(formId, field, context, values);
    }
    return _scalarField(
      formId: formId,
      field: field,
      holder: values,
      path: name,
      context: context,
    );
  }

  Widget _repeater(
    String formId,
    Json field,
    _RenderContext context,
    Map<String, dynamic> values,
  ) {
    final name = label(field['name'], '');
    final rows = values[name] is List
        ? (values[name] as List)
        : (values[name] = <dynamic>[]);
    final maxItems = field['maxItems'] is int ? field['maxItems'] as int : 100;
    final subFields = objects(field['fields']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label(field['label'], _humanize(name)),
          style: Theme.of(this.context).textTheme.titleSmall,
        ),
        for (var index = 0; index < rows.length; index++) ...[
          const SizedBox(height: 8),
          Panel(
            key: ObjectKey(rows[index]),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${label(field['label'], _humanize(name))} ${index + 1}',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: readOnly || mutationPending
                          ? null
                          : () {
                              final prefix = '$formId.$name.';
                              bool affected(String key) {
                                if (!key.startsWith(prefix)) return false;
                                final row = int.tryParse(
                                  key.substring(prefix.length).split('.').first,
                                );
                                return row != null && row >= index;
                              }

                              setState(() {
                                rows.removeAt(index);
                                _disposeControllersWhere(affected);
                                fieldErrors.removeWhere(
                                  (key, _) => affected(key),
                                );
                              });
                              // Rebind live sheet fields before their old indexed
                              // controllers are disposed at the end of this frame.
                              for (final refresh
                                  in _sheetRefresh.values.toList()) {
                                refresh();
                              }
                            },
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
                for (final sub in subFields) ...[
                  _scalarField(
                    formId: formId,
                    field: sub,
                    holder: rows[index] is Map
                        ? rows[index] as Map<String, dynamic>
                        : <String, dynamic>{},
                    path: '$name.$index.${label(sub['name'], '')}',
                    context: context,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: readOnly || mutationPending || rows.length >= maxItems
                ? null
                : () => setState(() {
                    rows.add(<String, dynamic>{});
                  }),
            icon: const Icon(Icons.add),
            label: Text('Add ${label(field['label'], _humanize(name))}'),
          ),
        ),
      ],
    );
  }

  void _changeField(
    String formId,
    Json field,
    Map<String, dynamic> holder,
    String path,
    Object? value,
  ) {
    if (mutationPending) return;
    final name = path.split('.').last;
    if (holder[name] == value) return;
    final parent = path.contains('.')
        ? path.substring(0, path.lastIndexOf('.') + 1)
        : '';
    final targets = (field['clearOnChange'] as List? ?? const [])
        .whereType<String>()
        .where((target) => target != name)
        .toList();
    setState(() {
      holder[name] = value;
      for (final target in targets) {
        holder.remove(target);
        final key = '$formId.$parent$target';
        _fieldEpochs[key] = (_fieldEpochs[key] ?? 0) + 1;
        _disposeControllersWhere(
          (candidate) => candidate == key || candidate.startsWith('$key.'),
        );
        fieldErrors.removeWhere(
          (candidate, _) => candidate == key || candidate.startsWith('$key.'),
        );
      }
    });
    if (targets.isNotEmpty) {
      for (final refresh in _sheetRefresh.values.toList()) {
        refresh();
      }
    }
  }

  Widget _scalarField({
    required String formId,
    required Json field,
    required Map<String, dynamic> holder,
    required String path,
    required _RenderContext context,
  }) {
    final name = path.split('.').last;
    final controllerKey = '$formId.$path';
    final controller = controllers.putIfAbsent(
      controllerKey,
      () => TextEditingController(
        text: holder[name] == null ? '' : '${holder[name]}',
      ),
    );
    final options = objects(field['options']);
    final optionsResource = label(field['optionsResource'], '');
    final error = fieldErrors['$formId.$path'];
    final decoration = InputDecoration(
      labelText: label(field['label'], _humanize(name)),
      errorText: error,
      enabled: !readOnly && !mutationPending,
      suffixIcon: field['nullable'] == true && holder[name] != null
          ? IconButton(
              tooltip: 'Clear',
              onPressed: readOnly || mutationPending
                  ? null
                  : () {
                      _changeField(formId, field, holder, path, null);
                      controller.clear();
                    },
              icon: const Icon(Icons.backspace_outlined),
            )
          : null,
    );
    void changed(Object? value) =>
        _changeField(formId, field, holder, path, value);

    if (label(field['type'], '') == 'select') {
      if (optionsResource.isNotEmpty) {
        return InputDecorator(
          key: ValueKey('field-$formId-$path'),
          decoration: decoration,
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: readOnly || mutationPending
                  ? null
                  : () => _pickResourceOption(
                      formId,
                      path,
                      field,
                      optionsResource,
                      holder,
                    ),
              child: Text(_optionLabel(optionsResource, holder[name])),
            ),
          ),
        );
      }
      final valuesSet = options
          .map((option) => label(option['value'], ''))
          .where((value) => value.isNotEmpty)
          .toSet();
      final selected = valuesSet.contains(holder[name]) ? holder[name] : null;
      return DropdownButtonFormField<String>(
        key: ValueKey(
          'field-$formId-$path-${_fieldEpochs[controllerKey] ?? 0}',
        ),
        initialValue: selected,
        decoration: decoration,
        items: [
          if (field['nullable'] == true)
            const DropdownMenuItem(value: '', child: Text('None')),
          for (final option in options)
            DropdownMenuItem(
              value: label(option['value'], ''),
              child: Text(label(option['label'], '')),
            ),
        ],
        onChanged: readOnly || mutationPending
            ? null
            : (value) => changed(value == null || value.isEmpty ? null : value),
      );
    }
    if (label(field['type'], '') == 'textarea' ||
        label(field['type'], '') == 'json') {
      return TextFormField(
        key: ValueKey('field-$formId-$path'),
        controller: controller,
        enabled: !readOnly && !mutationPending,
        maxLines: 4,
        decoration: decoration,
        onChanged: readOnly || mutationPending ? null : changed,
      );
    }
    if (label(field['type'], '') == 'number') {
      return TextFormField(
        key: ValueKey('field-$formId-$path'),
        controller: controller,
        enabled: !readOnly && !mutationPending,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: decoration,
        onChanged: readOnly || mutationPending
            ? null
            : (value) {
                changed(num.tryParse(value) ?? (value.isEmpty ? null : value));
              },
      );
    }
    return TextFormField(
      key: ValueKey('field-$formId-$path'),
      controller: controller,
      enabled: !readOnly && !mutationPending,
      keyboardType: label(field['type'], '') == 'date'
          ? TextInputType.datetime
          : TextInputType.text,
      decoration: decoration,
      onChanged: readOnly || mutationPending
          ? null
          : (value) {
              changed(
                value.trim().isEmpty
                    ? (field['nullable'] == true ? null : '')
                    : value,
              );
            },
    );
  }

  String _optionLabel(String resourceId, Object? value) {
    final items = pluginItems(resources[resourceId]?.data);
    final match = items.where((item) {
      final candidate = item['value'] ?? item['id'];
      return candidate == value;
    }).firstOrNull;
    if (match != null) {
      return label(
        match['label'],
        label(match['title'], label(match['name'], '$value')),
      );
    }
    return value == null ? 'None' : '$value';
  }

  Future<void> _pickResourceOption(
    String formId,
    String path,
    Json field,
    String resourceId,
    Map<String, dynamic> holder,
  ) async {
    if (!_stillCurrent() || mutationPending) return;
    final interaction = _interactionGeneration;
    final selected = await _pushOverlay<Object?>(
      DialogRoute<Object?>(
        context: context,
        builder: (dialog) => _ResourcePickerDialog(
          title: label(field['label'], 'Select'),
          transport: widget.transport,
          resourceId: resourceId,
          isCurrent: () =>
              _stillCurrent() && interaction == _interactionGeneration,
        ),
      ),
    );
    if (selected == null ||
        !_stillCurrent() ||
        interaction != _interactionGeneration ||
        mutationPending) {
      return;
    }
    _changeField(formId, field, holder, path, selected);
    setState(() {
      fieldErrors.remove('$formId.$path');
      controllers['$formId.$path']?.text = '$selected';
    });
  }

  Widget _button(Json component, _RenderContext context) {
    final labelText = _text(component['label'] ?? component['title'], context);
    if (labelText.isEmpty) return const SizedBox.shrink();
    final actionId = label(component['action'], '');
    final action = _spec.action(actionId);
    final disabled =
        readOnly ||
        mutationPending ||
        (action != null &&
            label(action['access'], 'member') == 'admin' &&
            !widget.allowAdminActions);
    if (action != null) {
      final pending = pendingActions.contains(actionId);
      return FilledButton(
        onPressed: pending || disabled
            ? null
            : () {
                final form = _forms
                    .where(
                      (form) =>
                          form['id'] == context.formId &&
                          form['action'] == actionId,
                    )
                    .firstOrNull;
                if (form != null) {
                  _submitForm(form, action, context);
                } else {
                  _runAction(action, component, context);
                }
              },
        child: Text(pending ? 'Working…' : labelText),
      );
    }
    final destination = _destination(component['destination'], context);
    if (destination != null) {
      return OutlinedButton(
        onPressed: () => widget.onNavigate(destination),
        child: Text(labelText),
      );
    }
    return FilledButton(onPressed: null, child: Text(labelText));
  }

  Widget _link(Json component, _RenderContext context) {
    final text = _text(component['label'] ?? component['title'], context);
    final destination = _destination(component['destination'], context);
    if (text.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: destination == null
            ? null
            : () => widget.onNavigate(destination),
        icon: const Icon(Icons.arrow_forward),
        label: Text(text),
      ),
    );
  }

  String? _destination(Object? value, _RenderContext context) {
    final raw = _resolve(value, context);
    if (raw is! String || raw.trim().isEmpty) return null;
    final trimmed = raw.trim();
    final key = normalizePluginPath(trimmed);
    final mapped = widget.allowedDestinations[key];
    if (mapped != null) return mapped;
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.hasScheme ||
        uri.host.isNotEmpty ||
        trimmed.contains('..')) {
      return null;
    }
    final path = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
    if (path == '/transactions' || path == '/activity') {
      final allowed = <String, String>{};
      for (final entry in uri.queryParameters.entries) {
        if (entry.key == 'accountId' || entry.key == 'accountIds') {
          allowed[entry.key] = entry.value;
        }
      }
      return allowed.isEmpty
          ? widget.allowedDestinations[path] ??
                widget.allowedDestinations['activity']
          : '/transactions?accountId=${Uri.encodeQueryComponent(uri.queryParameters['accountId'] ?? uri.queryParameters['accountIds'] ?? '')}';
    }
    return null;
  }

  Widget _detail(
    Json component,
    _RenderContext context,
    List<Widget> Function() children,
  ) {
    final title = _text(component['title'], context);
    final data = _resolve(component['data'], context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) SectionTitle(title),
        if (data is Map && objects(component['children']).isEmpty)
          _factsFromObject(data)
        else
          ...children(),
      ],
    );
  }

  List<Widget> _versionOne(BuildContext context, PluginPageDocument page) {
    final sections = objects(page.ui['sections']);
    return [
      for (final section in sections) ...[
        SectionTitle(label(section['title'], '')),
        for (final block in objects(section['blocks'])) _versionOneBlock(block),
      ],
    ];
  }

  Widget _versionOneBlock(Json block) => switch (label(block['type'], '')) {
    'text' => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(_display(block['text'])),
    ),
    'notice' => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _Notice(
        text: _display(block['text']),
        tone: label(block['tone'], 'info'),
      ),
    ),
    'link' => _versionOneLink(block),
    _ => const Panel(
      child: Text(
        'This page uses a feature that needs a newer version of GreenHouse.',
      ),
    ),
  };

  Widget _versionOneLink(Json block) {
    final destination =
        widget.allowedDestinations[normalizePluginPath(
          label(block['destination'], ''),
        )];
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: destination == null
            ? null
            : () => widget.onNavigate(destination),
        icon: const Icon(Icons.arrow_forward),
        label: Text(label(block['label'], 'Open')),
      ),
    );
  }

  String _itemTitle(Object? item) {
    if (item is Map) {
      for (final key in const ['title', 'name', 'label', 'displayName']) {
        final value = item[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    }
    return _display(item);
  }

  String _itemSubtitle(Object? item) {
    if (item is Map) {
      for (final key in const [
        'subtitle',
        'description',
        'summary',
        'detail',
      ]) {
        final value = item[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    }
    return '';
  }

  String _display(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is num || value is bool) return '$value';
    if (value is List) {
      return value.map(_display).where((part) => part.isNotEmpty).join(', ');
    }
    if (value is Map) {
      for (final key in const ['label', 'name', 'title', 'value', 'text']) {
        final candidate = value[key];
        if (candidate is String && candidate.trim().isNotEmpty) {
          return candidate.trim();
        }
        if (candidate is num || candidate is bool) return '$candidate';
      }
      return value.entries
          .where((entry) => entry.value is! Map && entry.value is! List)
          .map((entry) => '${_humanize(entry.key)}: ${_display(entry.value)}')
          .join(' · ');
    }
    return '$value';
  }
}

String _humanize(String value) {
  final words = value
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ')
      .trim();
  if (words.isEmpty) return value;
  return words[0].toUpperCase() + words.substring(1);
}

class PluginPageSpec {
  const PluginPageSpec({
    required this.version,
    required this.requiredCapabilities,
    required this.resources,
    required this.actions,
    required this.components,
    required this.roots,
  });

  final int version;
  final List<String> requiredCapabilities;
  final List<Json> resources;
  final List<Json> actions;
  final List<Json> components;
  final List<String> roots;

  factory PluginPageSpec.fromJson(Json json) => PluginPageSpec(
    version: json['version'] == 1 || json['version'] == 2
        ? json['version'] as int
        : 0,
    requiredCapabilities: json['requiredCapabilities'] is List
        ? (json['requiredCapabilities'] as List).whereType<String>().toList()
        : const [],
    resources: objects(json['resources']),
    actions: objects(json['actions']),
    components: objects(json['components']),
    roots: json['roots'] is List
        ? (json['roots'] as List).whereType<String>().toList()
        : const [],
  );

  bool get hasValidTree {
    final byId = {
      for (final component in components) component['id']: component,
    };
    if (byId.length != components.length ||
        byId.keys.any((id) => id is! String || id.isEmpty)) {
      return false;
    }
    var expanded = 0;
    bool visit(String id, Set<String> ancestors, int depth) {
      if (depth >= 8 || ancestors.contains(id) || ++expanded > 500) {
        return false;
      }
      final component = byId[id];
      if (component == null) return false;
      final children = component['children'];
      final emptyChildren = component['emptyChildren'];
      if ((children != null && children is! List) ||
          (emptyChildren != null && emptyChildren is! List)) {
        return false;
      }
      if ((children is List && children.length > 40) ||
          (emptyChildren is List && emptyChildren.length > 40)) {
        return false;
      }
      for (final child in [...?children as List?, ...?emptyChildren as List?]) {
        if (child is! String || !visit(child, {...ancestors, id}, depth + 1)) {
          return false;
        }
      }
      return true;
    }

    return roots.every((root) => visit(root, const {}, 0));
  }

  Json? resource(String id) =>
      resources.where((row) => row['id'] == id).firstOrNull;

  Json? action(String id) =>
      actions.where((row) => row['id'] == id).firstOrNull;
}

class _ResourcePickerDialog extends StatefulWidget {
  const _ResourcePickerDialog({
    required this.title,
    required this.transport,
    required this.resourceId,
    required this.isCurrent,
    this.returnItem = false,
    this.onResult,
  });

  final bool returnItem;
  final ValueChanged<PluginQueryResult>? onResult;
  final bool Function() isCurrent;
  final String title;
  final PluginPageTransport transport;
  final String resourceId;

  @override
  State<_ResourcePickerDialog> createState() => _ResourcePickerDialogState();
}

class _ResourcePickerDialogState extends State<_ResourcePickerDialog> {
  final search = TextEditingController();
  final focus = FocusNode();
  final List<Json> items = [];
  bool loading = true;
  bool hasMore = false;
  String? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_query());
  }

  @override
  void dispose() {
    search.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> _query({bool append = false}) async {
    if (!widget.isCurrent()) return;
    final current = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.transport.runQuery(widget.resourceId, {
        'search': search.text.trim(),
        'limit': 100,
        'offset': append ? items.length : 0,
      });
      if (!mounted || !widget.isCurrent() || current != generation) return;
      widget.onResult?.call(result);
      setState(() {
        if (!append) items.clear();
        items.addAll(pluginItems(result.data));
        hasMore = pluginHasMore(result.data);
        loading = false;
      });
    } catch (caught) {
      if (!mounted || !widget.isCurrent() || current != generation) return;
      setState(() {
        loading = false;
        error = errorMessage(caught);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Expanded(child: Text(widget.title)),
        IconButton(
          tooltip: 'Close choices',
          onPressed: () {
            focus.unfocus();
            Navigator.pop(context);
          },
          icon: const Icon(Icons.close),
        ),
      ],
    ),
    content: SizedBox(
      width: 460,
      height: 360,
      child: Column(
        children: [
          TextField(
            key: const ValueKey('resource-picker-search'),
            controller: search,
            focusNode: focus,
            textInputAction: TextInputAction.search,
            onChanged: (_) => _query(),
            onSubmitted: (_) {
              focus.unfocus();
              _query();
            },
            onTapOutside: (_) => focus.unfocus(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: 'Search',
              suffixIcon: IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  search.clear();
                  focus.unfocus();
                  _query();
                },
                icon: const Icon(Icons.close),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (loading && items.isEmpty)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (error != null)
            Expanded(child: Text(error!))
          else if (items.isEmpty)
            const Expanded(child: Center(child: Text('No matches.')))
          else
            Expanded(
              child: ListView.builder(
                key: const ValueKey('plugin-options-list'),
                itemCount: items.length + (hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= items.length) {
                    return TextButton(
                      onPressed: loading ? null : () => _query(append: true),
                      child: const Text('Load more'),
                    );
                  }
                  final item = items[index];
                  return ListTile(
                    title: Text(
                      label(
                        item['label'],
                        label(
                          item['title'],
                          label(item['name'], '${item['id']}'),
                        ),
                      ),
                    ),
                    onTap: () => Navigator.pop(
                      context,
                      widget.returnItem
                          ? item
                          : item['value'] ?? item['id'] ?? item['title'],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.tone});

  final String text;
  final String tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, color) = switch (tone) {
      'success' => (Icons.check_circle_outline, colors.primary),
      'warning' => (Icons.warning_amber_rounded, const Color(0xffa15c00)),
      'critical' => (Icons.error_outline, colors.error),
      _ => (Icons.info_outline, colors.secondary),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatefulWidget {
  const _SheetHandle({this.onClose});

  final VoidCallback? onClose;

  @override
  State<_SheetHandle> createState() => _SheetHandleState();
}

class _SheetHandleState extends State<_SheetHandle> {
  double dragDistance = 0;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('close-plugin-sheet'),
    button: true,
    label: 'Close details',
    child: GestureDetector(
      onVerticalDragStart: (_) => dragDistance = 0,
      onVerticalDragUpdate: (details) => dragDistance += details.delta.dy,
      onVerticalDragEnd: (details) {
        if (dragDistance > 60 || (details.primaryVelocity ?? 0) > 200) {
          (widget.onClose ?? () => Navigator.of(context).maybePop())();
        }
      },
      child: InkWell(
        onTap: widget.onClose ?? () => Navigator.of(context).maybePop(),
        child: SizedBox(
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 6),
              Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
