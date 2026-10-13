
import 'dart:async';

import 'package:country_state_city/country_state_city.dart' as csc;
import 'package:countries_world_map/countries_world_map.dart';
import 'package:countries_world_map/data/maps/world_map.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/map_selection_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/map_selection_service.dart';
import '../../localization/app_strings.dart';

class SharedMapScreen extends StatefulWidget {
  const SharedMapScreen({super.key});

  @override
  State<SharedMapScreen> createState() => _SharedMapScreenState();
}

class _SharedMapScreenState extends State<SharedMapScreen> {
  Stream<List<MapSelection>>? _selectionStream;
  List<MapSelection> _selections = const [];
  String? _selectedCountryCode;
  String? _selectedCountryName;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AuthProvider>().profile;
    final partnerId = profile?.pairedWith;
    if (profile != null && partnerId != null && partnerId.isNotEmpty) {
      _selectionStream = context
          .read<MapSelectionService>()
          .watchSelections(profile.id, partnerId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.read<AuthProvider>().profile;
    final partnerId = profile?.pairedWith;

    if (profile == null || partnerId == null || partnerId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(AppStrings.of(context).map)),
        body: Center(child: Text(AppStrings.of(context).pairFirst)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('📍 ${AppStrings.of(context).map}'),
        actions: [
          IconButton(
            tooltip: AppStrings.of(context).selections,
            icon: const Icon(Icons.list_alt_outlined),
            onPressed: () => _showSelectionsSheet(),
          ),
          IconButton(
            tooltip: AppStrings.of(context).help,
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfo(context),
          ),
        ],
      ),
      body: StreamBuilder<List<MapSelection>>(
        stream: _selectionStream,
        builder: (context, snapshot) {
          if (snapshot.hasData) _selections = snapshot.data!;

          return Column(
            children: [
              _buildHeader(profile.id, partnerId),
              Expanded(child: _buildWorldMap()),
              _buildBottomPanel(profile.id, partnerId),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(String userId, String partnerId) {
    final mine = _selections.where((s) => s.userId == userId).length;
    final partner = _selections.where((s) => s.userId == partnerId).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          _legendDot(Colors.amber.shade600, '${AppStrings.of(context).you} $mine'),
          SizedBox(width: 14),
          _legendDot(Colors.pink.shade400, '${AppStrings.of(context).partner} $partner'),
          SizedBox(width: 14),
          _legendDot(Colors.teal.shade400, AppStrings.of(context).together),
          Spacer(),
          OutlinedButton.icon(
            onPressed: _showCountryPicker,
            icon: const Icon(Icons.public, size: 17),
            label: Text(AppStrings.of(context).countrySelect),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  String _worldMapKey(String countryCode) {
    final code = countryCode.trim();
    if (code.length != 2) return code;
    final normalized = code.toUpperCase();
    final mapKeys = SMapWorldColors().toMap().keys;
    for (final key in mapKeys) {
      if (key.toUpperCase() == normalized) return key;
    }
    return '${normalized[0].toLowerCase()}${normalized[1].toUpperCase()}';
  }

  Widget _buildWorldMap() {
    final colors = <String, Color>{
      for (final entry in SMapWorldColors().toMap().entries)
        if (entry.value != null) entry.key: entry.value!,
    };
    final countryOwners = <String, Set<String>>{};

    for (final selection in _selections) {
      final code = _worldMapKey(selection.countryCode);
      countryOwners.putIfAbsent(code, () => <String>{}).add(selection.userId);
    }

    final profile = context.read<AuthProvider>().profile;
    final profileId = profile?.id;
    final partnerId = profile?.pairedWith;

    for (final entry in countryOwners.entries) {
      final owners = entry.value;
      final both = profileId != null &&
          partnerId != null &&
          owners.contains(profileId) &&
          owners.contains(partnerId);
      if (both) {
        colors[entry.key] = Colors.teal.shade400;
      } else if (profileId != null && owners.contains(profileId)) {
        colors[entry.key] = Colors.amber.shade600;
      } else {
        colors[entry.key] = Colors.pink.shade400;
      }
    }

    // Highlight the currently selected country immediately, even before the
    // database round-trip finishes. SimpleMap uses exact ISO-style IDs.
    if (_selectedCountryCode != null && _selectedCountryCode!.length == 2) {
      final key = _worldMapKey(_selectedCountryCode!);
      colors[key] = Theme.of(context).colorScheme.primary;
    }

    final citySelections = _selections
        .where((s) => s.cityName?.trim().isNotEmpty == true &&
            s.latitude != null &&
            s.longitude != null)
        .toList(growable: false);

    return InteractiveViewer(
      minScale: 0.75,
      maxScale: 30,
      boundaryMargin: const EdgeInsets.all(400),
      panEnabled: true,
      scaleEnabled: true,
      child: SizedBox(
        width: 1000,
        height: 500,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SimpleMap(
                  key: ValueKey(colors.entries.map((e) => '${e.key}:${e.value.value}').join('|')),
                  instructions: SMapWorld.instructions,
                  defaultColor: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF27313B)
                      : const Color(0xFFE7EBEF),
                  colors: colors,
                  countryBorder: CountryBorder(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF5B6670)
                        : Colors.white,
                    width: 1,
                  ),
                  callback: (id, name, _) => _countryTapped(id, name),
                ),
              ),
            ),
            ...citySelections.map((selection) {
              final x = ((selection.longitude! + 180) / 360 * 1000).clamp(8.0, 992.0);
              final y = ((90 - selection.latitude!) / 180 * 500).clamp(8.0, 492.0);
              final isMine = selection.userId == profileId;
              return Positioned(
                left: x - 10,
                top: y - 10,
                child: Tooltip(
                  message: [
                    selection.cityName,
                    if (selection.stateName?.trim().isNotEmpty == true) selection.stateName,
                    selection.countryName,
                  ].whereType<String>().where((v) => v.trim().isNotEmpty).join(', '),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: isMine ? Colors.amber.shade700 : Colors.pink.shade500,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black38)],
                    ),
                    child: const Icon(Icons.location_on, color: Colors.white, size: 13),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _countryTapped(String id, String name) async {
    final profile = context.read<AuthProvider>().profile;
    final partnerId = profile?.pairedWith;
    if (profile == null || partnerId == null || partnerId.isEmpty) return;

    final raw = id.trim();
    if (raw.length != 2) return;
    final code = _isoFromWorldMapKey(raw);
    if (code.isEmpty) return;
    await _selectCountry(code, name);
  }

  String _isoFromWorldMapKey(String mapId) {
    final value = mapId.trim();
    if (value.length != 2) return '';
    return value.toUpperCase();
  }

  Widget _buildBottomPanel(String userId, String partnerId) {
    final mySelections = _selections.where((s) => s.userId == userId).toList();
    final partnerSelections = _selections.where((s) => s.userId == partnerId).toList();
    final selected = _selectedCountryName;

    String label(MapSelection s) {
      final parts = <String>[];
      if (s.cityName?.trim().isNotEmpty == true) parts.add(s.cityName!.trim());
      if (s.stateName?.trim().isNotEmpty == true) parts.add(s.stateName!.trim());
      if (s.countryName.trim().isNotEmpty) parts.add(s.countryName.trim());
      return parts.join(', ');
    }

    final visible = _selections.reversed.take(4).toList();

    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.public, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      selected ?? AppStrings.of(context).countrySelect,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (_selectedCountryCode != null && _selectedCountryName != null)
                    TextButton.icon(
                      onPressed: () => _showCityPicker(_selectedCountryCode!, _selectedCountryName!),
                      icon: const Icon(Icons.location_city_outlined, size: 18),
                      label: Text(AppStrings.of(context).citySelect),
                    ),
                  if (mySelections.isNotEmpty || partnerSelections.isNotEmpty)
                    TextButton(
                      onPressed: _showSelectionsSheet,
                      child: Text('${_selections.length} ${AppStrings.of(context).selections.toLowerCase()}'),
                    ),
                ],
              ),
              if (visible.isNotEmpty) ...[
                SizedBox(height: 8),
                Text(AppStrings.of(context).selectedPlaces, style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, index) {
                      final selection = visible[index];
                      final mine = selection.userId == userId;
                      return Chip(
                        avatar: Icon(
                          selection.cityName?.trim().isNotEmpty == true ? Icons.location_city : Icons.public,
                          size: 17,
                        ),
                        label: Text(
                          '${label(selection)} · ${mine ? AppStrings.of(context).you : AppStrings.of(context).partner}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSelectionsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final profileId = context.read<AuthProvider>().profile?.id;

        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppStrings.of(context).selectedPlaces,
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${_selections.length} ${AppStrings.of(context).selections.toLowerCase()}',
                        style: TextStyle(
                          color: Theme.of(sheetContext)
                              .colorScheme
                              .onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1),
                Expanded(
                  child: _selections.isEmpty
                      ? Center(child: Text(AppStrings.of(context).noSavedPlaces))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          itemCount: _selections.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final selection = _selections[index];
                            final isMine = selection.userId == profileId;
                            final hasCity =
                                selection.cityName != null &&
                                selection.cityName!.trim().isNotEmpty;
                            final hasState =
                                selection.stateName != null &&
                                selection.stateName!.trim().isNotEmpty;

                            final placeParts = <String>[];
                            if (hasCity) placeParts.add(selection.cityName!.trim());
                            if (hasState) placeParts.add(selection.stateName!.trim());
                            if (selection.countryName.trim().isNotEmpty) placeParts.add(selection.countryName.trim());
                            final placeName = placeParts.join(', ');

                            final locationParts = <String>[];
                            if (hasState) {
                              locationParts.add(selection.stateName!.trim());
                            }
                            if (selection.countryName.trim().isNotEmpty) {
                              locationParts.add(selection.countryName.trim());
                            }
                            locationParts.add(isMine ? AppStrings.of(context).you : AppStrings.of(context).partner);

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              leading: CircleAvatar(
                                radius: 22,
                                backgroundColor: isMine
                                    ? Colors.amber.shade600
                                    : Colors.pink.shade400,
                                child: Icon(
                                  hasCity
                                      ? Icons.location_city_rounded
                                      : Icons.public_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(
                                placeName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  locationParts.join(' • '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              trailing: isMine
                                  ? IconButton(
                                      tooltip: AppStrings.of(context).deleteThisSelection,
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                      onPressed: () async {
                                        final confirmed =
                                            await showDialog<bool>(
                                          context: sheetContext,
                                          builder: (dialogContext) =>
                                              AlertDialog(
                                            title: Text(AppStrings.of(sheetContext).deleteSelectionTitle),
                                            content: Text(
                                              '${AppStrings.of(sheetContext).deleteSelectionConfirm}\n\n$placeName',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(
                                                  dialogContext,
                                                  false,
                                                ),
                                                child: Text(AppStrings.of(sheetContext).cancel),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(
                                                  dialogContext,
                                                  true,
                                                ),
                                                child: Text(AppStrings.of(sheetContext).delete),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirmed != true) return;

                                        try {
                                          await context
                                              .read<MapSelectionService>()
                                              .deleteSelection(selection.id);

                                          if (!mounted) return;
                                          setState(() {
                                            _selections = _selections
                                                .where((item) =>
                                                    item.id != selection.id)
                                                .toList();
                                          });
                                        } catch (e) {
                                          if (sheetContext.mounted) {
                                            ScaffoldMessenger.of(sheetContext)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  '${AppStrings.of(sheetContext).error}: $e',
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    )
                                  : null,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('📍 ${AppStrings.of(context).map}'),
        content: Text(AppStrings.of(context).mapSubtitle),
      ),
    );
  }

  Future<void> _showCountryPicker() async {
    try {
      final countries = await csc.getAllCountries();
      if (!mounted) return;
      countries.sort((a, b) => a.name.compareTo(b.name));
      final searchController = TextEditingController();
      List<csc.Country> filtered = List<csc.Country>.from(countries);

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              void filter(String value) {
                final query = value.trim().toLowerCase();
                setSheetState(() {
                  filtered = query.isEmpty
                      ? List<csc.Country>.from(countries)
                      : countries.where((country) {
                          return country.name.toLowerCase().contains(query) ||
                              country.isoCode.toLowerCase().contains(query);
                        }).toList();
                });
              }

              return SafeArea(
                child: SizedBox(
                  height: MediaQuery.of(sheetContext).size.height * .82,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(AppStrings.of(context).countrySelect, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: TextField(
                          controller: searchController,
                          onChanged: filter,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: AppStrings.of(context).searchCountry,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(child: Text(AppStrings.of(context).noCountries))
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, index) {
                                  final country = filtered[index];
                                  return ListTile(
                                    leading: Text(country.flag, style: const TextStyle(fontSize: 24)),
                                    title: Text(country.name),
                                    subtitle: Text(country.isoCode),
                                    onTap: () async {
                                      Navigator.pop(sheetContext);
                                      await _selectCountry(country.isoCode, country.name);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
      searchController.dispose();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStrings.of(context).locationDataFailed}: $e')));
      }
    }
  }

  Future<void> _selectCountry(String countryCode, String countryName) async {
    final profile = context.read<AuthProvider>().profile;
    final partnerId = profile?.pairedWith;
    if (profile == null || partnerId == null || partnerId.isEmpty) return;

    setState(() {
      _selectedCountryCode = countryCode.toUpperCase();
      _selectedCountryName = countryName;
    });

    try {
      await context.read<MapSelectionService>().saveCountry(
        userId: profile.id,
        partnerId: partnerId,
        countryCode: countryCode,
        countryName: countryName,
      );
      if (mounted) await _showCityPicker(countryCode.toUpperCase(), countryName);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStrings.of(context).save}: $e')));
    }
  }

  Future<void> _showCityPicker(String countryCode, String countryName) async {
    final profile = context.read<AuthProvider>().profile;
    final partnerId = profile?.pairedWith;
    if (profile == null || partnerId == null || partnerId.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.of(sheetContext).viewInsets.bottom + 24,
            ),
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    countryName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: 4),
                  Text(
                    '${AppStrings.of(context).regionSelect} → ${AppStrings.of(context).citySelect}',
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _OfflineLocationPicker(
                      countryCode: countryCode,
                      onSelected: (city, stateName) async {
                        try {
                          await context.read<MapSelectionService>().saveCity(
                                userId: profile.id,
                                partnerId: partnerId,
                                countryCode: countryCode,
                                countryName: countryName,
                                cityName: city.name,
                                stateName: stateName,
                                cityId: null,
                                latitude:
                                    double.tryParse(city.latitude ?? ''),
                                longitude:
                                    double.tryParse(city.longitude ?? ''),
                              );

                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        } catch (e) {
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(
                                content: Text('${AppStrings.of(context).save}: $e'),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: Text(AppStrings.of(context).close),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OfflineLocationPicker extends StatefulWidget {
  final String countryCode;
  final FutureOr<void> Function(csc.City city, String? stateName) onSelected;

  const _OfflineLocationPicker({
    required this.countryCode,
    required this.onSelected,
  });

  @override
  State<_OfflineLocationPicker> createState() => _OfflineLocationPickerState();
}

class _OfflineLocationPickerState extends State<_OfflineLocationPicker> {
  final TextEditingController _controller = TextEditingController();

  List<csc.State> _states = const [];
  List<csc.City> _cities = const [];

  csc.State? _selectedState;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadStates();
  }

  Future<void> _loadStates() async {
    try {
      final states = await csc.getStatesOfCountry(widget.countryCode);

      if (!mounted) return;

      states.sort(
        (a, b) => _normalize(a.name).compareTo(_normalize(b.name)),
      );

      setState(() {
        _states = states;
        _loading = false;
      });

      // Some countries in the dataset may not have administrative states.
      // In that case, fall back to the country's city records.
      if (states.isEmpty) {
        await _loadCountryCities();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _loadCountryCities() async {
    try {
      final cities = await csc.getCountryCities(widget.countryCode);

      if (!mounted) return;

      cities.sort(
        (a, b) => _normalize(a.name).compareTo(_normalize(b.name)),
      );

      setState(() {
        _cities = cities;
        _selectedState = null;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
      });
    }
  }

  Future<void> _selectState(csc.State state) async {
    _controller.clear();

    setState(() {
      _selectedState = state;
      _cities = const [];
      _loading = true;
      _loadError = null;
    });

    try {
      final cities = await csc.getStateCities(
        widget.countryCode,
        state.isoCode,
      );

      if (!mounted) return;

      cities.sort(
        (a, b) => _normalize(a.name).compareTo(_normalize(b.name)),
      );

      setState(() {
        _cities = cities;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  void _backToStates() {
    _controller.clear();
    setState(() {
      _selectedState = null;
      _cities = const [];
      _loading = false;
      _loadError = null;
    });
  }

  String _normalize(String value) {
    var normalized = value.toLowerCase().trim();

    const replacements = <String, String>{
      'ı': 'i',
      'ş': 's',
      'ğ': 'g',
      'ü': 'u',
      'ö': 'o',
      'ç': 'c',
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ñ': 'n',
      'ý': 'y',
    };

    for (final entry in replacements.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }

    return normalized;
  }

  List<csc.State> get _filteredStates {
    final query = _normalize(_controller.text);
    if (query.isEmpty) return _states;

    return _states
        .where((state) => _normalize(state.name).contains(query))
        .toList();
  }

  List<csc.City> get _filteredCities {
    final query = _normalize(_controller.text);
    if (query.isEmpty) return _cities;

    return _cities
        .where((city) => _normalize(city.name).contains(query))
        .toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: SingleChildScrollView(
          child: Text('${AppStrings.of(context).locationDataFailed}: $_loadError'),
        ),
      );
    }

    if (_selectedState == null && _states.isNotEmpty) {
      final states = _filteredStates;

      return Column(
        children: [
          TextField(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: AppStrings.of(context).regionSelect,
              hintText: AppStrings.of(context).stateOrRegionHint,
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 12),
          Expanded(
            child: states.isEmpty
                ? Center(child: Text(AppStrings.of(context).noRegions))
                : ListView.separated(
                    itemCount: states.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final state = states[index];

                      return ListTile(
                        leading: const Icon(Icons.map_outlined),
                        title: Text(state.name),
                        subtitle: Text(state.isoCode),
                        onTap: () => _selectState(state),
                      );
                    },
                  ),
          ),
        ],
      );
    }

    // Countries without states/regions fall back to their country-wide
    // city/town/district dataset.
    if (_selectedState == null && _states.isEmpty) {
      final cities = _filteredCities;

      return Column(
        children: [
          TextField(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: AppStrings.of(context).citySelect,
              hintText: AppStrings.of(context).searchCity,
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 12),
          Expanded(
            child: cities.isEmpty
                ? Center(child: Text(AppStrings.of(context).noCities))
                : ListView.separated(
                    itemCount: cities.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final city = cities[index];

                      return ListTile(
                        leading: const Icon(Icons.location_city),
                        title: Text(city.name),
                        onTap: () => widget.onSelected(city, null),
                      );
                    },
                  ),
          ),
        ],
      );
    }

    final cities = _filteredCities;

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: AppStrings.of(context).backToRegions,
              onPressed: _backToStates,
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                _selectedState!.name,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        TextField(
          controller: _controller,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: AppStrings.of(context).citySelect,
            hintText: AppStrings.of(context).cityHint,
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
        SizedBox(height: 12),
        Expanded(
          child: cities.isEmpty
              ? Center(child: Text(AppStrings.of(context).noCities))
              : ListView.separated(
                  itemCount: cities.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final city = cities[index];

                    return ListTile(
                      leading: const Icon(Icons.location_city),
                      title: Text(city.name),
                      onTap: () => widget.onSelected(
                        city,
                        _selectedState!.name,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}


