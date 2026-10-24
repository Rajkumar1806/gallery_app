import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';

import '../data/gallery_scope.dart';
import '../data/grouping.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _text = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<AssetEntity> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _run(q));
  }

  void _run(String q) {
    final repo = GalleryScope.of(context, listen: false);
    setState(() {
      _query = q.trim();
      _results = _query.isEmpty ? const [] : repo.search(_query);
    });
  }

  void _useSuggestion(String s) {
    _text.text = s;
    _text.selection = TextSelection.collapsed(offset: s.length);
    _run(s);
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Glass(
                    radius: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      controller: _text,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: _onChanged,
                      onSubmitted: _run,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        icon: Icon(Icons.search, color: GalleryColors.subtle(b)),
                        hintText: 'Times, places, file names…',
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _text.clear();
                                  _run('');
                                },
                              ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(child: _query.isEmpty ? _suggestions(context) : _resultsView(context)),
          ]),
        ),
      ),
    );
  }

  Widget _resultsView(BuildContext context) {
    final b = Theme.of(context).brightness;
    if (_results.isEmpty) {
      return Center(
        child: Text('No results for “$_query”',
            style: TextStyle(color: GalleryColors.subtle(b))),
      );
    }
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text('${_results.length} results',
              style: TextStyle(color: GalleryColors.subtle(b))),
        ),
      ),
      ...groupedGridSlivers(context, groups: groupByDay(_results), columns: 4),
      SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24)),
    ]);
  }

  Widget _suggestions(BuildContext context) {
    final repo = GalleryScope.of(context);
    final monthFmt = DateFormat('MMMM yyyy');
    final months = <String>[];
    for (final a in repo.all) {
      final m = monthFmt.format(a.createDateTime);
      if (!months.contains(m)) months.add(m);
      if (months.length == 6) break;
    }

    Widget section(String title, List<String> items, IconData icon) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Text(title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in items)
              ActionChip(
                avatar: Icon(icon, size: 18),
                label: Text(s),
                onPressed: () => _useSuggestion(s),
                shape: const StadiumBorder(),
                side: BorderSide.none,
                backgroundColor: GalleryColors.glass(Theme.of(context).brightness),
              ),
          ]),
        ),
      ]);
    }

    return ListView(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
      children: [
        section('Quick', ['Videos', 'Favorite', 'Screenshot'], Icons.bolt_outlined),
        section('Times', months, Icons.event_outlined),
        section('Places', [for (final p in repo.scanner.places.take(8)) p.name],
            Icons.place_outlined),
        section('Things', repo.scanner.tagged.keys.take(10).toList(), Icons.sell_outlined),
        section('Albums', [for (final a in repo.albums.take(10)) a.name],
            Icons.photo_album_outlined),
      ],
    );
  }
}
