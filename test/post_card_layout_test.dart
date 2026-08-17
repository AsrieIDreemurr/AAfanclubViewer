import 'package:aafanclub_viewer/domain/forum_document.dart';
import 'package:aafanclub_viewer/ui/aa_text.dart';
import 'package:aafanclub_viewer/ui/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('balances the post header and body horizontal insets', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PostCard(
            post: ForumPost(
              number: '637',
              name: '影',
              date: '2026年08月17日 21:46:53',
              id: 'kagJDFhS',
              body: '正文',
            ),
          ),
        ),
      ),
    );

    final headerLeft =
        tester.getTopLeft(find.byKey(const Key('post-header-637'))).dx;
    final bodyLeft =
        tester.getTopLeft(find.byKey(const Key('post-body-637'))).dx;

    expect(headerLeft, 8);
    expect(bodyLeft, 16);
    expect(bodyLeft - headerLeft, 8);
  });

  testWidgets('AA lines may grow for taller fallback and link glyphs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AaText('>> 636 魔法☆社畜'))),
    );

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.softWrap, isFalse);
    expect(text.strutStyle?.forceStrutHeight, isFalse);

    final scroller = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroller.scrollDirection, Axis.horizontal);
    expect(scroller.padding, const EdgeInsets.symmetric(vertical: 1));
  });
}
