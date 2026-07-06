# Hermes Companion iOS App - Design Handoff Document

## Project Overview
Hermes Companion is a native iOS client for the Hermes Agent platform, providing a seamless interface for interacting with AI agents through text and voice conversations. The app currently has a functional but inconsistent UI that needs a unified design language.

## Current State
- Basic glassmorphism theme with cyberpunk elements
- Inconsistent styling across different views
- Limited design system with minimal color palette
- Voice conversation features with Matrix-style visualization
- Session management and chat interface

## Design Goals
1. Create a cohesive design language that unifies all app screens
2. Enhance the cyberpunk aesthetic while maintaining usability
3. Implement a consistent component library
4. Improve visual hierarchy and information architecture
5. Create a distinctive brand identity that reflects the Hermes platform

## Target Platforms
- iOS (iPhone and iPad)
- Minimum iOS version: 17.0

## Brand Identity
### Colors
- Primary: #00B398 (Chibi teal)
- CTA: #F2A900 (Amber)
- Danger: #CF4520 (Red-orange)
- Background: #162032 (Dark blue)
- Surface: #1E2A40 (Slightly lighter blue)
- Text: #FFFFFF (White) for primary, #B0B0B0 (Light gray) for secondary

### Typography
- Primary: Hanken Grotesk (modern sans-serif)
- Secondary: Inter (clean and readable)
- Hierarchy: Clear distinction between headers, body text, and captions

### Iconography
- SF Symbols for standard iOS icons
- Custom icons for Hermes-specific features
- Consistent stroke weights and visual style

## Key Features & Screens

### 1. Connection Setup Screen
- Brand logo and app name
- Server connection configuration
- Version display
- Quick connect options

### 2. Session List Screen
- List of conversation sessions
- Session creation and management
- Search and filtering capabilities
- Session metadata display

### 3. Chat Screen
- Main conversation interface
- Message bubbles with distinct styling for user/assistant
- Input bar with text, voice, and attachment options
- Real-time tool progress indicators
- Model selection dropdown

### 4. Voice Conversation Screen
- Full-screen voice interface
- Cyberpunk Matrix-style visualization
- Audio level indicators
- Conversation controls (start/stop)
- Real-time transcription display

### 5. Settings Screen
- Account and connection settings
- Voice configuration
- Theme selection
- Model preferences
- About and version information

## Design Requirements

### Visual Style
1. **Glassmorphism**: Frosted glass effects with subtle transparency
2. **Cyberpunk Elements**: Neon accents, digital aesthetics, futuristic feel
3. **Liquid Glass**: Smooth, flowing transitions and surfaces
4. **Dark Theme**: Primary dark mode with vibrant accent colors

### Component Library
1. **Buttons**: Primary, secondary, and icon buttons with consistent styling
2. **Input Fields**: Text fields with glass effect and clear focus states
3. **Cards**: Content containers with depth and subtle shadows
4. **Navigation**: Tab bar and navigation patterns that fit iOS conventions
5. **Progress Indicators**: Custom loaders for AI processing states
6. **Voice Visualization**: Animated audio level indicators

### Animations & Transitions
1. **Micro-interactions**: Subtle feedback for user actions
2. **Page Transitions**: Smooth navigation between screens
3. **Voice Visualization**: Dynamic Matrix-style rain animation
4. **Loading States**: Engaging progress indicators

### Responsive Design
1. **iPhone Layouts**: Optimized for various iPhone screen sizes
2. **iPad Layouts**: Expanded layouts that utilize larger screen real estate
3. **Orientation Support**: Portrait and landscape layouts

## Technical Constraints
- SwiftUI framework
- iOS 17+ compatibility
- Native iOS components preferred
- Performance considerations for real-time voice processing
- Accessibility compliance

## Deliverables Needed
1. **Design System**: Complete component library with specifications
2. **Screen Designs**: High-fidelity mockups for all key screens
3. **Style Guide**: Color palette, typography, spacing guidelines
4. **Icon Set**: Custom icons for Hermes-specific features
5. **Animation Specifications**: Details for key animations and transitions
6. **Responsive Layouts**: Designs for different screen sizes and orientations

## Handoff Format
Please provide:
- Figma or Sketch files with all designs
- Exported assets (icons, images) in appropriate formats
- Design specifications document
- Component library with usage guidelines
- Responsive design guidelines

## Timeline
This design handoff should be completed within 2 weeks, with iterative feedback cycles as needed.

## Next Steps
Once the design is complete, I will implement the unified look and feel in the Hermes Companion iOS app, ensuring all components are properly integrated and functional.