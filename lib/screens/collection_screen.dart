import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/assets.dart';
import '../core/audio.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/game_controller.dart';
import '../widgets/ui.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GameController>();
    final items = tab == 0 ? Catalog.fruits : Catalog.rares;
    final owned = tab == 0 ? g.fruits : g.rares;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const CoverBg(A.bgGrove),
          const Vignette(dark: 0.32),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      RoundIconBtn(
                        icon: Icons.arrow_back,
                        onTap: () {
                          AudioHub.I.close();
                          Navigator.pop(context);
                        },
                      ),
                      Expanded(child: TitleBanner(tab == 0 ? 'Fruit Collection' : 'Rare Collection')),
                      const SizedBox(width: 46),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${owned.length} / ${items.length} found',
                    style: Lf.body.copyWith(color: Lf.goldHot),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: GroveButton(
                          label: 'FRUITS',
                          height: 42,
                          fontSize: 15,
                          color: tab == 0 ? Lf.meadow : Lf.wood,
                          dark: tab == 0 ? Lf.forest : Lf.woodDark,
                          onTap: () => setState(() => tab = 0),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GroveButton(
                          label: 'RARES',
                          height: 42,
                          fontSize: 15,
                          color: tab == 1 ? Lf.goldDark : Lf.wood,
                          dark: tab == 1 ? const Color(0xFF7A560C) : Lf.woodDark,
                          onTap: () => setState(() => tab = 1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final it = items[i];
                        final have = owned.contains(it.id);
                        return WoodPanel(
                          gold: have,
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              Expanded(
                                child: Opacity(
                                  opacity: have ? 1 : 0.28,
                                  child: Sprite(it.sprite),
                                ),
                              ),
                              Text(
                                have ? it.name : '???',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: Lf.body.copyWith(fontSize: 11),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
