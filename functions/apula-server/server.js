import express from "express";
import cors from "cors";
import bodyParser from "body-parser";
import dotenv from "dotenv";
import nodemailer from "nodemailer";
import { Resend } from "resend";

dotenv.config();

const app = express();

app.use(cors());
app.use(bodyParser.json());

const resendApiKey = String(process.env.RESEND_API_KEY || "").trim();
const resend = resendApiKey ? new Resend(resendApiKey) : null;
const senderEmail = String(
  process.env.EMAIL_FROM || process.env.EMAIL_USER || "",
).trim();

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || "smtp.gmail.com",
  port: Number(process.env.SMTP_PORT || 587),
  secure: String(process.env.SMTP_SECURE || "false").toLowerCase() === "true",
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASS,
  },
  connectionTimeout: 10000,
  greetingTimeout: 10000,
  socketTimeout: 15000,
});

app.get("/health", (_req, res) => {
  res.status(200).json({
    status: "ok",
    service: "apula-server",
    timestamp: new Date().toISOString(),
  });
});

app.post("/send-verification", async (req, res) => {
  const { email, code } = req.body;

  if (!email || !code) {
    return res.status(400).json({ error: "Missing email or code" });
  }

  const mailOptions = {
    from: `"Apula" <${senderEmail}>`,
    to: email,
    subject: "Your Apula Verification Code",
    html: `
      <div style="font-family: Arial, sans-serif; padding: 20px;">
        <h2 style="color: #A30000;">Apula Email Verification</h2>
        <p>Here’s your 6-digit verification code:</p>
        <h1 style="letter-spacing: 5px; color: #A30000;">${code}</h1>
        <p>This code will expire in 10 minutes.</p>
        <p>If you didn’t request this, please ignore this email.</p>
      </div>
    `,
  };

  try {
    if (resend && senderEmail) {
      const resendResult = await Promise.race([
        resend.emails.send({
          from: `Apula <${senderEmail}>`,
          to: [email],
          subject: mailOptions.subject,
          html: mailOptions.html,
        }),
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error("Resend email send timeout")), 15000),
        ),
      ]);

      if (resendResult?.error) {
        throw new Error(`Resend error: ${resendResult.error.message || "Unknown resend error"}`);
      }
    } else {
      await Promise.race([
        transporter.sendMail(mailOptions),
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error("SMTP email send timeout")), 15000),
        ),
      ]);
    }

    console.log(`✅ Email sent to ${email}`);
    res.status(200).json({ message: "Verification email sent successfully" });
  } catch (error) {
    console.error("❌ Error sending email:", error);
    res.status(500).json({ error: "Failed to send verification email" });
  }
});

const PORT = process.env.PORT || 3007;
app.listen(PORT, "0.0.0.0", () => {
  console.log(`✅ Server running on http://0.0.0.0:${PORT}`);
});
