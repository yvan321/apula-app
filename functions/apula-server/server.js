import express from "express";
import cors from "cors";
import bodyParser from "body-parser";
import dotenv from "dotenv";
import nodemailer from "nodemailer";

dotenv.config();

const app = express();

app.use(cors());
app.use(bodyParser.json());

const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASS,
  },
});

app.post("/send-verification", async (req, res) => {
  const { email, code } = req.body;

  if (!email || !code) {
    return res.status(400).json({ error: "Missing email or code" });
  }

  const mailOptions = {
    from: `"Apula" <${process.env.EMAIL_USER}>`,
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
    await transporter.sendMail(mailOptions);
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
