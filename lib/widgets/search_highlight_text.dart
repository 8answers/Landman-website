import 'package:flutter/material.dart';

class SearchHighlightText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final Color highlightColor;

  const SearchHighlightText({
    super.key,
    required this.text,
    required this.query,
    required this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.highlightColor = const Color(0xFFFFFF00),
  });

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim();
    if (text.isEmpty || normalizedQuery.isEmpty) {
      return Text(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = normalizedQuery.toLowerCase();
    if (!lowerText.contains(lowerQuery)) {
      return Text(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
      );
    }

    final spans = <TextSpan>[];
    var cursor = 0;

    while (cursor < text.length) {
      final matchIndex = lowerText.indexOf(lowerQuery, cursor);
      if (matchIndex < 0) {
        spans.add(TextSpan(text: text.substring(cursor)));
        break;
      }

      if (matchIndex > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, matchIndex)));
      }

      final matchEnd = matchIndex + normalizedQuery.length;
      spans.add(
        TextSpan(
          text: text.substring(matchIndex, matchEnd),
          style: style.copyWith(
            backgroundColor: highlightColor,
          ),
        ),
      );
      cursor = matchEnd;
    }

    return Text.rich(
      TextSpan(
        style: style,
        children: spans,
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
    );
  }
}
