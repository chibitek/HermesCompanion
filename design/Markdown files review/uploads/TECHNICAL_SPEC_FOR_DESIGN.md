# Hermes Companion iOS App - Technical Specification for Design

## App Structure Overview

### Main Components
1. **ConnectionSetupView** - Initial server connection screen
2. **SessionListView** - List of conversation sessions
3. **ChatView** - Main chat interface with message display
4. **VoiceConversationPage** - Full-screen voice conversation interface
5. **SettingsView** - Configuration and preferences
6. **GlassTheme** - Custom UI components with glassmorphism effects

### Key Functional Areas

#### 1. Chat Interface
- Real-time streaming messages with tool progress indicators
- Message bubbles for user and assistant with distinct styling
- Input bar with text entry, voice input, and attachment options
- Model selection dropdown with provider filtering
- Session management controls

#### 2. Voice Conversation
- Real-time speech-to-text transcription
- Text-to-speech synthesis with voice customization
- Audio level visualization with Matrix-style digital rain
- Barge-in support (user can interrupt AI while speaking)
- Conversation mode switching (local/remote/premium)

#### 3. Session Management
- Create, view, and manage conversation sessions
- Session metadata display (title, model, timestamp)
- Message history with user and assistant messages
- Attachment handling (images, files)

#### 4. Settings & Configuration
- Server connection settings
- Voice configuration (speed, pitch, voice selection)
- Theme preferences
- Model and provider preferences
- Premium voice service integration

## Current UI Components

### GlassInputBar
Custom input bar with:
- Text entry field with glass effect
- Voice conversation button
- Attachment button
- Send button with state-aware icon
- Model picker dropdown

### Message Bubbles
- User messages (right-aligned, accent colored)
- Assistant messages (left-aligned, surface colored)
- Tool progress indicators with real-time updates
- Error messages with danger styling

### Voice Visualization
- Matrix-style digital rain animation
- Audio level indicators
- Conversation state indicators
- Cyberpunk color schemes

### Session List Items
- Session title and metadata
- Last message preview
- Timestamp display
- Model indicator

## Design Challenges to Address

### 1. Visual Consistency
- Inconsistent styling across different views
- Mixed design languages (glassmorphism, cyberpunk, standard iOS)
- Lack of unified component library

### 2. Information Architecture
- Complex feature set needs clear organization
- Voice and text conversation modes need distinct but cohesive UI
- Settings hierarchy could be better organized

### 3. User Experience
- Voice conversation flow needs intuitive controls
- Model selection process could be simplified
- Real-time tool progress needs clear visualization

### 4. Responsive Design
- iPad layouts need optimization for larger screens
- Orientation changes need smooth transitions
- Voice conversation screen needs adaptive layout

## Technical Considerations for Design

### Performance Constraints
- Real-time voice processing requires efficient UI updates
- Streaming messages need smooth rendering
- Matrix visualization should maintain 60fps

### Accessibility Requirements
- VoiceOver support for all interactive elements
- Sufficient color contrast for readability
- Dynamic text sizing support

### iOS Design Guidelines
- Follow Human Interface Guidelines for native feel
- Use appropriate navigation patterns (tab bar, navigation stack)
- Implement standard iOS gestures and interactions

## Key Interactions to Design

### 1. Voice Conversation Flow
- Starting a voice conversation
- Real-time transcription display
- AI response playback
- Conversation interruption (barge-in)
- Ending a conversation

### 2. Chat Interaction
- Sending text messages
- Receiving streaming responses
- Tool execution visualization
- Attachment handling

### 3. Navigation
- Moving between sessions
- Accessing settings
- Switching between chat and voice modes
- Session management actions

### 4. Configuration
- Server connection setup
- Voice settings customization
- Model selection
- Theme preferences

## Assets and Branding

### Current Brand Elements
- Chibi teal (#00B398) as primary color
- Amber (#F2A900) for calls-to-action
- Dark blue background (#162032)
- Glassmorphism effects throughout

### Needed Design Assets
- Custom icons for Hermes-specific features
- Loading animations and progress indicators
- Voice visualization components
- Session and message icons
- Brand logo variations

## Integration Points

### 1. Voice Conversation Page
- Full-screen cyberpunk visualization
- Audio level indicators
- Conversation controls
- Real-time transcription display

### 2. Settings Screens
- Voice configuration interface
- Model selection UI
- Theme customization
- Account and connection settings

### 3. Chat Interface
- Message bubble styling
- Input bar design
- Tool progress visualization
- Session management controls

## Success Metrics for Design

### Usability Goals
- Intuitive voice conversation initiation
- Clear visual hierarchy in chat interface
- Easy model and provider selection
- Responsive and performant UI

### Aesthetic Goals
- Cohesive cyberpunk glassmorphism theme
- Consistent component styling
- Engaging visual feedback
- Professional yet distinctive appearance

## Handoff Expectations

### Design Deliverables
1. High-fidelity mockups for all key screens
2. Component library with specifications
3. Style guide with color, typography, and spacing
4. Icon set for Hermes-specific features
5. Animation specifications for key interactions
6. Responsive layouts for different screen sizes

### Technical Specifications
1. Color values in hex and system formats
2. Typography scales and weights
3. Component dimensions and padding
4. Animation timing and easing curves
5. Accessibility contrast ratios
6. Export specifications for assets

This technical specification should provide the design team with a comprehensive understanding of the Hermes Companion app's current functionality and design needs. The goal is to create a unified, visually striking, and highly functional interface that enhances the user experience while maintaining the distinctive cyberpunk aesthetic.