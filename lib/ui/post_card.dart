import 'package:flutter/material.dart';

import '../domain/forum_document.dart';
import 'aa_text.dart';

class PostCard extends StatelessWidget {
  const PostCard({required this.post, this.onLinkTap, super.key});

  final ForumPost post;
  final ValueChanged<Uri>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    const headerStyle = TextStyle(
      fontFamily: 'Saitamaar',
      fontSize: 16,
      height: 1,
      color: Colors.black,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SelectionArea(
              key: Key('post-header-${post.number}'),
              child: Text.rich(
                TextSpan(
                  style: headerStyle,
                  children: [
                    TextSpan(text: '${post.number} ： '),
                    if (post.name != null)
                      TextSpan(
                        text: post.name,
                        style: TextStyle(
                          color:
                              post.authorIsTrip
                                  ? const Color(0xff008000)
                                  : Colors.black,
                          fontWeight:
                              post.authorIsTrip
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                        ),
                      ),
                    if (post.date != null) TextSpan(text: ' ： ${post.date}'),
                    if (post.id != null) TextSpan(text: ' ID:${post.id}'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: AaText(
              post.body,
              key: Key('post-body-${post.number}'),
              runs: post.bodyRuns,
              onLinkTap: onLinkTap,
            ),
          ),
        ],
      ),
    );
  }
}
