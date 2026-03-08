import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../issue_detail/presentation/issue_detail_page.dart';
import 'report_notifier.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Supported values
// ─────────────────────────────────────────────────────────────────────────────

const _kCategories = <String, String>{
  'road_damage':  'Road Damage',
  'garbage':      'Garbage',
  'electricity':  'Electricity',
  'water':        'Water',
  'safety':       'Public Safety',
  'corruption':   'Corruption',
  'other':        'Other',
};

const _kCities = ['Pune', 'Mumbai', 'Bangalore'];

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class ReportIssuePage extends ConsumerStatefulWidget {
  const ReportIssuePage({super.key});

  @override
  ConsumerState<ReportIssuePage> createState() => _ReportIssuePageState();
}

class _ReportIssuePageState extends ConsumerState<ReportIssuePage> {
  final _formKey      = GlobalKey<FormState>();
  final _titleCtrl    = TextEditingController();
  final _descCtrl     = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Navigate to IssueDetailPage when submission succeeds.
    ref.listen<ReportFormState>(reportNotifierProvider, (_, next) {
      if (next.isSuccess && next.submittedPostId != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => IssueDetailPage(postId: next.submittedPostId!),
          ),
        );
      }
    });

    final state     = ref.watch(reportNotifierProvider);
    final notifier  = ref.read(reportNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Report an Issue'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Error banner ─────────────────────────────────────────────
              if (state.errorMessage != null) ...[
                _ErrorBanner(message: state.errorMessage!),
                const SizedBox(height: 12),
              ],

              // ── Section: Details ─────────────────────────────────────────
              _SectionHeader(label: 'Issue Details'),
              const SizedBox(height: 8),

              TextFormField(
                controller:  _titleCtrl,
                maxLength:   200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText:   'Title *',
                  hintText:    'e.g. Large pothole on main road',
                  prefixIcon:  Icon(Icons.title),
                  border:      OutlineInputBorder(),
                ),
                onChanged: notifier.updateTitle,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller:   _descCtrl,
                maxLength:    1000,
                maxLines:     4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText:          'Description *',
                  hintText:           'Describe the issue in detail…',
                  prefixIcon:         Icon(Icons.description),
                  alignLabelWithHint: true,
                  border:             OutlineInputBorder(),
                ),
                onChanged: notifier.updateDescription,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Description is required' : null,
              ),
              const SizedBox(height: 24),

              // ── Section: Classification ───────────────────────────────────
              _SectionHeader(label: 'Classification'),
              const SizedBox(height: 8),

              // Category dropdown
              DropdownButtonFormField<String>(
                initialValue: state.category,
                hint:        const Text('Select a category *'),
                decoration:  const InputDecoration(
                  prefixIcon: Icon(Icons.category),
                  border:     OutlineInputBorder(),
                ),
                items: _kCategories.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ))
                    .toList(),
                onChanged: notifier.updateCategory,
                validator: (v) => v == null ? 'Please select a category' : null,
              ),
              const SizedBox(height: 12),

              // City dropdown
              DropdownButtonFormField<String>(
                initialValue: state.city,
                hint:       const Text('City *'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.location_city),
                  border:     OutlineInputBorder(),
                ),
                items: _kCities
                    .map((c) => DropdownMenuItem(value: c.toLowerCase(), child: Text(c)))
                    .toList(),
                onChanged: notifier.updateCity,
                validator: (v) => v == null ? 'Select your city' : null,
              ),
              const SizedBox(height: 24),

              // ── Section: Location ─────────────────────────────────────────
              _SectionHeader(label: 'Location'),
              const SizedBox(height: 8),
              _LocationTile(state: state, notifier: notifier),
              const SizedBox(height: 24),

              // ── Section: Photo ────────────────────────────────────────────
              _SectionHeader(label: 'Photo (optional)'),
              const SizedBox(height: 8),
              _ImagePicker(state: state, notifier: notifier),
              const SizedBox(height: 32),

              // ── Submit button ─────────────────────────────────────────────
              FilledButton.icon(
                onPressed: state.isSubmitting
                    ? null
                    : () {
                        if (!state.hasLocation) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please detect your location first.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        if (_formKey.currentState?.validate() ?? false) {
                          notifier.submit();
                        }
                      },
                icon: state.isSubmitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child:     CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(state.isSubmitting ? 'Submitting…' : 'Submit Report'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Location tile
// ─────────────────────────────────────────────────────────────────────────────

class _LocationTile extends StatelessWidget {
  const _LocationTile({required this.state, required this.notifier});

  final ReportFormState state;
  final ReportNotifier  notifier;

  @override
  Widget build(BuildContext context) {
    if (state.isLocating) {
      return const ListTile(
        leading:  SizedBox.square(
          dimension: 24,
          child:     CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Detecting location…'),
        tileColor: Colors.transparent,
      );
    }

    if (state.hasLocation) {
      return ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
          ),
        ),
        leading: Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary),
        title:   const Text('Location captured'),
        subtitle: Text(
          '${state.lat!.toStringAsFixed(5)}, ${state.lng!.toStringAsFixed(5)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: IconButton(
          onPressed: notifier.detectLocation,
          icon: const Icon(Icons.refresh),
          tooltip: 'Retake',
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: notifier.detectLocation,
      icon:  const Icon(Icons.my_location),
      label: const Text('Detect My Location *'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image picker tile
// ─────────────────────────────────────────────────────────────────────────────

class _ImagePicker extends StatelessWidget {
  const _ImagePicker({required this.state, required this.notifier});

  final ReportFormState state;
  final ReportNotifier  notifier;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (state.imageFile != null) {
      return Stack(
        alignment: Alignment.topRight,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(state.imageFile!.path),
              height:     200,
              width:      double.infinity,
              fit:        BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(4),
            child: IconButton.filled(
              onPressed: notifier.clearImage,
              icon:      const Icon(Icons.close, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.errorContainer,
                foregroundColor: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => notifier.pickImage(ImageSource.camera),
            icon:      const Icon(Icons.camera_alt),
            label:     const Text('Camera'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => notifier.pickImage(ImageSource.gallery),
            icon:      const Icon(Icons.photo_library),
            label:     const Text('Gallery'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color:        cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: cs.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
