/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import {
  Body,
  Button,
  Container,
  Head,
  Heading,
  Hr,
  Html,
  Preview,
  Section,
  Text,
} from 'npm:@react-email/components@0.0.22'
import type { TemplateEntry } from './registry.ts'

interface WelcomeProps {
  clinicName?: string
  dashboardUrl?: string
}

const WelcomeEmail = ({
  clinicName,
  dashboardUrl = 'https://patientping.health/dashboard',
}: WelcomeProps) => (
  <Html lang="en" dir="ltr">
    <Head />
    <Preview>Welcome to Patientping — never lose a patient to a missed follow-up.</Preview>
    <Body style={main}>
      <Container style={container}>
        <Section style={header}>
          <Heading style={brand}>Patientping</Heading>
        </Section>

        <Section style={card}>
          <Heading style={h1}>
            {clinicName ? `Welcome, ${clinicName}!` : 'Welcome to Patientping!'}
          </Heading>
          <Text style={text}>
            Thank you for joining Patientping. You now have everything you need to
            keep your patients on track and never miss a follow-up.
          </Text>
          <Text style={text}>
            Here's what you can do next:
          </Text>
          <Text style={listItem}>• Add your first patients</Text>
          <Text style={listItem}>• Set up follow-up date</Text>
          <Text style={listItem}>• Send reminder for medication, check-ups, medication, or feedback.</Text>

          <Section style={buttonWrap}>
            <Button href={dashboardUrl} style={button}>
              Continue to Dashboard
            </Button>
          </Section>

          <Hr style={hr} />

          <Text style={replyText}>
            Have a question or need help? Just reply to this email — we read
            every message.
          </Text>
        </Section>

        <Text style={footer}>
          Patientping · Care that follows through
        </Text>
      </Container>
    </Body>
  </Html>
)

export const template = {
  component: WelcomeEmail,
  subject: 'Welcome to Patientping',
  displayName: 'Welcome email',
  previewData: { clinicName: 'Sunrise Medical Center' },
} satisfies TemplateEntry

// Brand colors derived from index.css
// --primary: 174 72% 36% → hsl(174, 72%, 36%) → #19a591
// --primary-glow: 168 76% 48% → #1fd9b6
// --foreground: 190 40% 12% → #122529
// --muted-foreground: 190 15% 42% → #5b7077
// --border: 180 18% 88% → #d8e2e2

const main: React.CSSProperties = {
  backgroundColor: '#ffffff',
  fontFamily:
    "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif",
  margin: 0,
  padding: 0,
}

const container: React.CSSProperties = {
  maxWidth: '560px',
  margin: '0 auto',
  padding: '32px 20px',
}

const header: React.CSSProperties = {
  textAlign: 'center' as const,
  padding: '8px 0 24px',
}

const brand: React.CSSProperties = {
  fontFamily: "'Sora', 'Inter', sans-serif",
  fontSize: '22px',
  fontWeight: 700,
  color: '#19a591',
  margin: 0,
  letterSpacing: '-0.01em',
}

const card: React.CSSProperties = {
  backgroundColor: '#ffffff',
  border: '1px solid #d8e2e2',
  borderRadius: '12px',
  padding: '32px 28px',
  boxShadow: '0 1px 2px rgba(18, 37, 41, 0.04)',
}

const h1: React.CSSProperties = {
  fontFamily: "'Sora', 'Inter', sans-serif",
  fontSize: '24px',
  fontWeight: 700,
  color: '#122529',
  margin: '0 0 16px',
  lineHeight: 1.3,
}

const text: React.CSSProperties = {
  fontSize: '15px',
  color: '#3a4f55',
  lineHeight: 1.6,
  margin: '0 0 14px',
}

const listItem: React.CSSProperties = {
  fontSize: '15px',
  color: '#3a4f55',
  lineHeight: 1.7,
  margin: '0 0 4px',
  paddingLeft: '4px',
}

const buttonWrap: React.CSSProperties = {
  textAlign: 'center' as const,
  padding: '24px 0 8px',
}

const button: React.CSSProperties = {
  backgroundColor: '#19a591',
  color: '#ffffff',
  fontSize: '15px',
  fontWeight: 600,
  textDecoration: 'none',
  padding: '12px 28px',
  borderRadius: '10px',
  display: 'inline-block',
}

const hr: React.CSSProperties = {
  border: 'none',
  borderTop: '1px solid #e8eeee',
  margin: '24px 0 16px',
}

const replyText: React.CSSProperties = {
  fontSize: '14px',
  color: '#5b7077',
  lineHeight: 1.5,
  margin: 0,
}

const footer: React.CSSProperties = {
  fontSize: '12px',
  color: '#8a9ba0',
  textAlign: 'center' as const,
  margin: '24px 0 0',
}
