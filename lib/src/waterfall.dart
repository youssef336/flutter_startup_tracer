import 'advice.dart';
import 'model.dart';
import 'report.dart';

const int _labelWidth = 30;

class _Row {
  _Row(this.label, this.start, {this.end, this.fill = '#', this.note = ''});

  final String label;
  final Duration start;
  final Duration? end;
  final String fill;
  final String note;

  bool get isPoint => end == null;
}

String _num(Duration? d) => d == null ? '' : (d.inMicroseconds / 1000).round().toString();

String _label(String text) {
  if (text.length <= _labelWidth) {
    return text.padRight(_labelWidth);
  }
  return '${text.substring(0, _labelWidth - 2)}..';
}

List<_Row> _rows(StartupReport report) {
  final List<(Duration, List<_Row>)> blocks = <(Duration, List<_Row>)>[];

  void addSpan(StartupSpan span, int depth, List<_Row> into) {
    final String indent = '  ' * depth;
    final String prefix = switch (span.kind) {
      StartupSpanKind.group => '[parallel] ',
      StartupSpanKind.deferred => '(deferred) ',
      _ => '',
    };
    final List<String> notes = <String>[
      if (span.isSync) 'sync',
      if (span.kind == StartupSpanKind.group && span.duration != null)
        'wall ${_num(span.duration)} / sum ${_num(span.childrenSum)} ms',
      if (span.end == null) 'still running',
      if (span.error != null) 'FAILED',
    ];
    into.add(
      _Row(
        '$indent$prefix${span.name}',
        span.start,
        end: span.end ?? report.timelineEnd,
        fill: span.isDeferred ? '~' : (span.kind == StartupSpanKind.group ? '=' : '#'),
        note: notes.join(', '),
      ),
    );
    for (final StartupSpan child in span.children) {
      addSpan(child, depth + 1, into);
    }
  }

  for (final StartupSpan span in report.spans) {
    final List<_Row> rows = <_Row>[];
    addSpan(span, 0, rows);
    blocks.add((span.start, rows));
  }
  for (final StartupMark mark in report.marks) {
    blocks.add((mark.at, <_Row>[_Row('* ${mark.name}', mark.at)]));
  }
  void milestone(String name, Duration? at) {
    if (at != null) {
      blocks.add((at, <_Row>[_Row('> $name', at)]));
    }
  }

  milestone('runApp', report.runApp);
  milestone('first frame built', report.firstFrameBuilt);
  milestone('first frame rasterized', report.firstFrameRasterized);
  if (report.interactive != null) {
    milestone('interactive: ${report.interactiveName}', report.interactive);
  }

  // Stable sort by start time keeps spans before marks recorded at the same
  // instant, and children right under their parent.
  final List<int> order = List<int>.generate(blocks.length, (int i) => i)
    ..sort((int a, int b) {
      final int byTime = blocks[a].$1.compareTo(blocks[b].$1);
      return byTime != 0 ? byTime : a.compareTo(b);
    });
  return <_Row>[for (final int i in order) ...blocks[i].$2];
}

/// Renders the waterfall lines (header + one line per row).
List<String> renderWaterfall(StartupReport report, {int barWidth = 40}) {
  final int width = barWidth < 10 ? 10 : barWidth;
  final int endUs = report.timelineEnd.inMicroseconds;
  final double scale = endUs <= 0 ? 0 : width / endUs;

  int pos(Duration d) {
    final int p = (d.inMicroseconds * scale).floor();
    return p < 0 ? 0 : (p >= width ? width - 1 : p);
  }

  const String left = '0';
  final String right = '${_num(report.timelineEnd)} ms';
  final String axis = left + right.padLeft(width - left.length);
  final List<String> lines = <String>[
    '${_label('phase')} ${'start'.padLeft(6)} ${'ms'.padLeft(6)} |$axis|',
  ];

  for (final _Row row in _rows(report)) {
    final List<String> bar = List<String>.filled(width, ' ');
    if (row.isPoint) {
      bar[pos(row.start)] = '|';
    } else {
      final int a = pos(row.start);
      final int b = (row.end!.inMicroseconds * scale).ceil().clamp(a + 1, width);
      for (int i = a; i < b; i++) {
        bar[i] = row.fill;
      }
    }
    final String duration = row.isPoint ? '' : _num(row.end! - row.start);
    final String note = row.note.isEmpty ? '' : ' ${row.note}';
    lines.add(
      '${_label(row.label)} ${_num(row.start).padLeft(6)} ${duration.padLeft(6)} '
      '|${bar.join()}|$note',
    );
  }
  return lines;
}

String _severity(StartupAdvice advice) =>
    advice.severity == StartupAdviceSeverity.warning ? '[!]' : '[i]';

/// The console report: summary, waterfall, advice.
String renderPretty(StartupReport report, {int barWidth = 40}) {
  final StringBuffer out = StringBuffer()
    ..writeln(
      '== Startup trace (${report.buildMode}) - total ${fmtMs(report.total)}'
      '${report.complete ? '' : ' (incomplete)'} ==',
    );
  for (final (String key, String value) in report.summary()) {
    out.writeln('${key.padRight(28)}: $value');
  }
  out.writeln();
  renderWaterfall(report, barWidth: barWidth).forEach(out.writeln);
  out.writeln('legend: # phase  = parallel group  ~ deferred  | instant  * mark  > milestone');
  if (report.advice.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Advice:');
    for (final StartupAdvice advice in report.advice) {
      out.writeln('  ${_severity(advice)} ${advice.message}');
    }
  }
  return out.toString().trimRight();
}

String _cell(String text) => text.replaceAll('|', r'\|');

/// The Markdown report.
String renderMarkdown(StartupReport report, {int barWidth = 40}) {
  final StringBuffer out = StringBuffer()
    ..writeln('## Startup report')
    ..writeln()
    ..writeln('| | |')
    ..writeln('|---|---|')
    ..writeln('| build mode | ${report.buildMode} |')
    ..writeln('| total | **${fmtMs(report.total)}**${report.complete ? '' : ' (incomplete)'} |');
  for (final (String key, String value) in report.summary()) {
    out.writeln('| ${_cell(key)} | ${_cell(value)} |');
  }

  out
    ..writeln()
    ..writeln('### Phases')
    ..writeln()
    ..writeln('| phase | kind | start (ms) | duration (ms) | notes |')
    ..writeln('|---|---|---:|---:|---|');
  void row(StartupSpan span, int depth) {
    final String name = '${'&nbsp;&nbsp;' * depth}${_cell(span.name)}';
    final List<String> notes = <String>[
      if (span.isSync) 'sync',
      if (span.kind == StartupSpanKind.group) 'sum ${_num(span.childrenSum)} ms',
      if (span.error != null) 'failed: ${_cell(span.error!)}',
    ];
    out.writeln(
      '| $name | ${span.kind.name} | ${_num(span.start)} | '
      '${span.duration == null ? 'running' : _num(span.duration)} | ${notes.join(', ')} |',
    );
    for (final StartupSpan child in span.children) {
      row(child, depth + 1);
    }
  }

  for (final StartupSpan span in report.spans) {
    row(span, 0);
  }

  out
    ..writeln()
    ..writeln('### Waterfall')
    ..writeln()
    ..writeln('```text');
  renderWaterfall(report, barWidth: barWidth).forEach(out.writeln);
  out.writeln('```');

  if (report.advice.isNotEmpty) {
    out
      ..writeln()
      ..writeln('### Advice')
      ..writeln();
    for (final StartupAdvice advice in report.advice) {
      out.writeln('- **${advice.severity.name}**: ${advice.message}');
    }
  }
  return out.toString().trimRight();
}
